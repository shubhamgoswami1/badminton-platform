"""
Tournament discovery tests — join / duplicate-join / nearby / my-hosted / my-joined.

Covers the gaps not addressed in test_tournaments.py:
  - POST /{id}/participants — happy path
  - POST /{id}/participants — duplicate join → 409
  - POST /{id}/participants — join after registration closed → 409
  - POST /{id}/participants — organiser cannot join own tournament → 403
  - GET /tournaments/nearby — returns tournament within radius
  - GET /tournaments/nearby — excludes tournament outside radius
  - GET /tournaments/nearby — excludes tournaments without GPS coords
  - GET /tournaments/my-hosted — returns tournaments created by user
  - GET /tournaments/my-joined — returns tournaments the user has joined
  - GET /tournaments/my-joined — does NOT return tournaments user only hosted

Sample payloads are shown inline inside the helpers below.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

# ── Phone numbers ─────────────────────────────────────────────────────────

PHONE_ORG   = "+911111111101"   # organiser / host
PHONE_P1    = "+911111111102"   # player 1 (will join)
PHONE_P2    = "+911111111103"   # player 2

# Mumbai (Azad Maidan): 18.9312° N, 72.8313° E
_MUMBAI_LAT = 18.9312
_MUMBAI_LNG = 72.8313

# Pune (130 km from Mumbai): 18.5204° N, 73.8567° E
_PUNE_LAT = 18.5204
_PUNE_LNG = 73.8567


# ── Helpers ───────────────────────────────────────────────────────────────


def _t_payload(**overrides) -> dict:
    """
    Sample tournament creation payload.

    Defaults:
      {
        "title": "Discovery Open 2026",
        "city": "Mumbai",
        "format": "KNOCKOUT",
        "match_format": "BEST_OF_3",
        "play_type": "SINGLES",
        "max_participants": 8
      }
    """
    base = {
        "title": "Discovery Open 2026",
        "city": "Mumbai",
        "format": "KNOCKOUT",
        "match_format": "BEST_OF_3",
        "play_type": "SINGLES",
        "max_participants": 8,
    }
    base.update(overrides)
    return base


async def _create(client: AsyncClient, token: str, **overrides) -> dict:
    """Create a tournament and return the response data dict."""
    r = await client.post(
        "/api/v1/tournaments",
        json=_t_payload(**overrides),
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 201, r.text
    return r.json()["data"]


async def _open_registration(client: AsyncClient, token: str, tid: str) -> None:
    """Transition tournament to REGISTRATION_OPEN."""
    r = await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200, r.text


async def _join(
    client: AsyncClient, token: str, tid: str, *, partner_user_id: str | None = None
) -> dict:
    """
    Sample join payload:
      POST /api/v1/tournaments/{id}/participants
      {"partner_user_id": null}
    """
    body: dict = {}
    if partner_user_id:
        body["partner_user_id"] = partner_user_id
    r = await client.post(
        f"/api/v1/tournaments/{tid}/participants",
        json=body,
        headers={"Authorization": f"Bearer {token}"},
    )
    return r


# ── Join tests ────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_join_tournament_happy_path(client: AsyncClient, db_session: AsyncSession):
    """
    A player can join a tournament in REGISTRATION_OPEN status.

    POST /api/v1/tournaments/{id}/participants
    → 201, participant record returned
    """
    org = await _do_full_login(client, PHONE_ORG)
    p1  = await _do_full_login(client, PHONE_P1)

    t = await _create(client, org["access_token"])
    await _open_registration(client, org["access_token"], t["id"])

    r = await _join(client, p1["access_token"], t["id"])
    assert r.status_code == 201, r.text
    data = r.json()["data"]
    assert data["tournament_id"] == t["id"]
    assert data["status"] == "REGISTERED"
    assert data["partner_user_id"] is None


@pytest.mark.asyncio
async def test_join_tournament_doubles_with_partner(client: AsyncClient, db_session: AsyncSession):
    """
    Player 1 can register with a partner_user_id for a DOUBLES tournament.

    POST /api/v1/tournaments/{id}/participants
    {"partner_user_id": "<p2-user-id>"}
    → 201, both user_id and partner_user_id are in the response
    """
    org = await _do_full_login(client, PHONE_ORG)
    p1  = await _do_full_login(client, PHONE_P1)
    p2  = await _do_full_login(client, PHONE_P2)

    # Get p2's user_id via /users/me
    me_r = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {p2['access_token']}"},
    )
    p2_user_id = me_r.json()["data"]["user"]["id"]

    t = await _create(client, org["access_token"], play_type="DOUBLES")
    await _open_registration(client, org["access_token"], t["id"])

    r = await _join(client, p1["access_token"], t["id"], partner_user_id=p2_user_id)
    assert r.status_code == 201, r.text
    data = r.json()["data"]
    assert data["partner_user_id"] == p2_user_id


@pytest.mark.asyncio
async def test_join_tournament_duplicate_returns_409(
    client: AsyncClient, db_session: AsyncSession
):
    """
    A user cannot register twice for the same tournament.

    POST /api/v1/tournaments/{id}/participants  (second time)
    → 409 CONFLICT
    """
    org = await _do_full_login(client, PHONE_ORG)
    p1  = await _do_full_login(client, PHONE_P1)

    t = await _create(client, org["access_token"])
    await _open_registration(client, org["access_token"], t["id"])

    # First join — should succeed
    r1 = await _join(client, p1["access_token"], t["id"])
    assert r1.status_code == 201, r1.text

    # Second join — must be rejected
    r2 = await _join(client, p1["access_token"], t["id"])
    assert r2.status_code == 409, r2.text


@pytest.mark.asyncio
async def test_join_tournament_when_not_open_returns_409(
    client: AsyncClient, db_session: AsyncSession
):
    """
    Cannot join a tournament that is still in DRAFT status.

    POST /api/v1/tournaments/{id}/participants  (status=DRAFT)
    → 409 CONFLICT
    """
    org = await _do_full_login(client, PHONE_ORG)
    p1  = await _do_full_login(client, PHONE_P1)

    t = await _create(client, org["access_token"])  # stays DRAFT

    r = await _join(client, p1["access_token"], t["id"])
    assert r.status_code == 409, r.text


@pytest.mark.asyncio
async def test_organiser_cannot_join_own_tournament(
    client: AsyncClient, db_session: AsyncSession
):
    """
    The tournament organiser is forbidden from registering as a participant.

    POST /api/v1/tournaments/{id}/participants  (as organiser)
    → 403 FORBIDDEN
    """
    org = await _do_full_login(client, PHONE_ORG)

    t = await _create(client, org["access_token"])
    await _open_registration(client, org["access_token"], t["id"])

    r = await _join(client, org["access_token"], t["id"])
    assert r.status_code == 403, r.text


@pytest.mark.asyncio
async def test_join_requires_auth(client: AsyncClient, db_session: AsyncSession):
    """Joining without a token returns 401."""
    org = await _do_full_login(client, PHONE_ORG)
    t = await _create(client, org["access_token"])
    await _open_registration(client, org["access_token"], t["id"])

    r = await client.post(f"/api/v1/tournaments/{t['id']}/participants", json={})
    assert r.status_code == 401


# ── Nearby tests ──────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_nearby_returns_tournament_within_radius(
    client: AsyncClient, db_session: AsyncSession
):
    """
    A tournament pinned at Mumbai appears when searching from Mumbai within 50 km.

    GET /api/v1/tournaments/nearby?lat=18.9312&lng=72.8313&radius_km=50
    → 200, tournament in results, distance_km <= 50
    """
    org = await _do_full_login(client, PHONE_ORG)

    # Create tournament with GPS pin at Mumbai
    t = await _create(
        client, org["access_token"],
        title="Mumbai Nearby Test",
        latitude=_MUMBAI_LAT,
        longitude=_MUMBAI_LNG,
    )

    r = await client.get(
        "/api/v1/tournaments/nearby",
        params={"lat": _MUMBAI_LAT, "lng": _MUMBAI_LNG, "radius_km": 50},
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 200, r.text
    body = r.json()["data"]
    ids = [item["id"] for item in body["items"]]
    assert t["id"] in ids

    # Distance must be attached and ≤ radius
    matched = next(item for item in body["items"] if item["id"] == t["id"])
    assert matched["distance_km"] is not None
    assert matched["distance_km"] <= 50.0


@pytest.mark.asyncio
async def test_nearby_excludes_tournament_outside_radius(
    client: AsyncClient, db_session: AsyncSession
):
    """
    A tournament pinned at Pune (~130 km away) should NOT appear in a 50 km
    search centred on Mumbai.

    GET /api/v1/tournaments/nearby?lat=18.9312&lng=72.8313&radius_km=50
    → 200, Pune tournament NOT in results
    """
    org = await _do_full_login(client, PHONE_ORG)

    t_pune = await _create(
        client, org["access_token"],
        title="Pune Nearby Test",
        city="Pune",
        latitude=_PUNE_LAT,
        longitude=_PUNE_LNG,
    )

    r = await client.get(
        "/api/v1/tournaments/nearby",
        params={"lat": _MUMBAI_LAT, "lng": _MUMBAI_LNG, "radius_km": 50},
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 200, r.text
    ids = [item["id"] for item in r.json()["data"]["items"]]
    assert t_pune["id"] not in ids


@pytest.mark.asyncio
async def test_nearby_excludes_tournaments_without_gps(
    client: AsyncClient, db_session: AsyncSession
):
    """
    A tournament created without lat/lng is never returned in a nearby search.

    GET /api/v1/tournaments/nearby?lat=18.9312&lng=72.8313&radius_km=200
    → 200, text-only tournament NOT in results
    """
    org = await _do_full_login(client, PHONE_ORG)

    t_no_gps = await _create(
        client, org["access_token"],
        title="No GPS Tournament",
        city="Mumbai",
        # no latitude / longitude
    )

    r = await client.get(
        "/api/v1/tournaments/nearby",
        params={"lat": _MUMBAI_LAT, "lng": _MUMBAI_LNG, "radius_km": 200},
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 200, r.text
    ids = [item["id"] for item in r.json()["data"]["items"]]
    assert t_no_gps["id"] not in ids


@pytest.mark.asyncio
async def test_nearby_requires_auth(client: AsyncClient):
    """Nearby endpoint requires authentication."""
    r = await client.get(
        "/api/v1/tournaments/nearby",
        params={"lat": _MUMBAI_LAT, "lng": _MUMBAI_LNG},
    )
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_nearby_requires_lat_lng(client: AsyncClient, db_session: AsyncSession):
    """Nearby endpoint must reject requests missing lat or lng."""
    org = await _do_full_login(client, PHONE_ORG)

    r = await client.get(
        "/api/v1/tournaments/nearby",
        params={"lat": _MUMBAI_LAT},  # missing lng
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 422  # Unprocessable Entity — FastAPI validation


# ── My-hosted tests ───────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_my_hosted_returns_created_tournaments(
    client: AsyncClient, db_session: AsyncSession
):
    """
    GET /api/v1/tournaments/my-hosted returns only tournaments created by the caller.
    """
    org = await _do_full_login(client, PHONE_ORG)
    other = await _do_full_login(client, PHONE_P1)

    t_mine   = await _create(client, org["access_token"],   title="Mine")
    t_theirs = await _create(client, other["access_token"], title="Theirs")

    r = await client.get(
        "/api/v1/tournaments/my-hosted",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 200, r.text
    ids = [t["id"] for t in r.json()["data"]]
    assert t_mine["id"] in ids
    assert t_theirs["id"] not in ids


@pytest.mark.asyncio
async def test_my_hosted_requires_auth(client: AsyncClient):
    r = await client.get("/api/v1/tournaments/my-hosted")
    assert r.status_code == 401


# ── My-joined tests ───────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_my_joined_returns_joined_tournaments(
    client: AsyncClient, db_session: AsyncSession
):
    """
    GET /api/v1/tournaments/my-joined returns only tournaments the caller joined.
    """
    org = await _do_full_login(client, PHONE_ORG)
    p1  = await _do_full_login(client, PHONE_P1)

    t_joined     = await _create(client, org["access_token"], title="Joined")
    t_not_joined = await _create(client, org["access_token"], title="Not Joined")

    await _open_registration(client, org["access_token"], t_joined["id"])
    r = await _join(client, p1["access_token"], t_joined["id"])
    assert r.status_code == 201, r.text

    r = await client.get(
        "/api/v1/tournaments/my-joined",
        headers={"Authorization": f"Bearer {p1['access_token']}"},
    )
    assert r.status_code == 200, r.text
    ids = [t["id"] for t in r.json()["data"]]
    assert t_joined["id"] in ids
    assert t_not_joined["id"] not in ids


@pytest.mark.asyncio
async def test_my_joined_does_not_include_hosted(
    client: AsyncClient, db_session: AsyncSession
):
    """
    Tournaments a user organised but never joined should NOT appear in my-joined.
    """
    org = await _do_full_login(client, PHONE_ORG)

    t = await _create(client, org["access_token"], title="Hosted Only")

    r = await client.get(
        "/api/v1/tournaments/my-joined",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 200, r.text
    ids = [item["id"] for item in r.json()["data"]]
    assert t["id"] not in ids


@pytest.mark.asyncio
async def test_my_joined_requires_auth(client: AsyncClient):
    r = await client.get("/api/v1/tournaments/my-joined")
    assert r.status_code == 401
