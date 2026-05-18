"""
Player discovery refinement tests — search combinations.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_A = "+919100000001"
PHONE_B = "+919100000002"
PHONE_C = "+919100000003"


async def _login_and_profile(
    client: AsyncClient,
    phone: str,
    **profile_fields,
) -> str:
    t = await _do_full_login(client, phone)
    token = t["access_token"]
    base = {"display_name": "Player", "city": "Mumbai", "skill_level": "INTERMEDIATE"}
    base.update(profile_fields)
    await client.put(
        "/api/v1/users/me/profile",
        json=base,
        headers={"Authorization": f"Bearer {token}"},
    )
    return token


# ── Text search ───────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_text_query_prefix_match(client: AsyncClient, db_session: AsyncSession):
    token = await _login_and_profile(client, PHONE_A, display_name="Arjun Sharma")
    await _login_and_profile(client, PHONE_B, display_name="Priya Mehta")

    r = await client.get(
        "/api/v1/discovery/players?q=Arj",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert len(data) >= 1
    assert all(d["display_name"].lower().startswith("arj") for d in data)


@pytest.mark.asyncio
async def test_text_query_no_match_returns_empty(client: AsyncClient, db_session: AsyncSession):
    token = await _login_and_profile(client, PHONE_A, display_name="Arjun Sharma")

    r = await client.get(
        "/api/v1/discovery/players?q=Zzznomatch",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200
    assert r.json()["meta"]["total"] == 0


# ── Elo range ─────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_elo_min_filter(client: AsyncClient, db_session: AsyncSession):
    """Only players with elo_rating >= elo_min should appear."""
    token_a = await _login_and_profile(client, PHONE_A, display_name="HighElo")
    token_b = await _login_and_profile(client, PHONE_B, display_name="LowElo")

    # Set elo via the internal model directly so we don't need a match endpoint.
    from users.models import PlayerProfile
    from sqlalchemy import select

    async def _set_elo(phone: str, elo: float) -> None:
        from tests.test_auth import _do_full_login as dfl
        t = await dfl(client, phone)
        me = (await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {t['access_token']}"},
        )).json()["data"]
        uid = me["id"]
        result = await db_session.execute(
            select(PlayerProfile).where(PlayerProfile.user_id == uid)
        )
        profile = result.scalar_one_or_none()
        if profile:
            profile.elo_rating = elo
            await db_session.flush()

    await _set_elo(PHONE_A, 1700.0)
    await _set_elo(PHONE_B, 1200.0)
    await db_session.commit()

    r = await client.get(
        "/api/v1/discovery/players?elo_min=1500",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert r.status_code == 200
    for p in r.json()["data"]:
        assert p["elo_rating"] is not None and p["elo_rating"] >= 1500


@pytest.mark.asyncio
async def test_elo_max_filter(client: AsyncClient, db_session: AsyncSession):
    """Only players with elo_rating <= elo_max should appear."""
    token_a = await _login_and_profile(client, PHONE_A, display_name="HighElo2")
    token_b = await _login_and_profile(client, PHONE_B, display_name="LowElo2")

    from users.models import PlayerProfile
    from sqlalchemy import select

    async def _set_elo(phone: str, elo: float) -> None:
        from tests.test_auth import _do_full_login as dfl
        t = await dfl(client, phone)
        me = (await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {t['access_token']}"},
        )).json()["data"]
        uid = me["id"]
        result = await db_session.execute(
            select(PlayerProfile).where(PlayerProfile.user_id == uid)
        )
        profile = result.scalar_one_or_none()
        if profile:
            profile.elo_rating = elo
            await db_session.flush()

    await _set_elo(PHONE_A, 1800.0)
    await _set_elo(PHONE_B, 1100.0)
    await db_session.commit()

    r = await client.get(
        "/api/v1/discovery/players?elo_max=1300",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert r.status_code == 200
    # Players with elo > 1300 must not appear.
    for p in r.json()["data"]:
        assert p["elo_rating"] is None or p["elo_rating"] <= 1300


# ── Combined filters ──────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_combined_city_and_text_query(client: AsyncClient, db_session: AsyncSession):
    token = await _login_and_profile(
        client, PHONE_A, display_name="Rohit Singh", city="Bangalore"
    )
    await _login_and_profile(
        client, PHONE_B, display_name="Rohit Verma", city="Delhi"
    )

    r = await client.get(
        "/api/v1/discovery/players?city=Bangalore&q=Rohit",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert len(data) >= 1
    for p in data:
        assert p["city"].lower() == "bangalore"
        assert p["display_name"].lower().startswith("rohit")


@pytest.mark.asyncio
async def test_response_includes_stats_fields(client: AsyncClient, db_session: AsyncSession):
    token = await _login_and_profile(client, PHONE_A, display_name="StatsCheck")

    r = await client.get(
        "/api/v1/discovery/players",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert len(data) >= 1
    p = data[0]
    assert "elo_rating" in p
    assert "matches_played" in p
    assert "wins" in p
    assert "losses" in p
    assert "reliability_score" in p


# ── Location search ───────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_location_radius_filter(client: AsyncClient, db_session: AsyncSession):
    """Players within radius appear; those outside do not."""
    token_a = await _login_and_profile(client, PHONE_A, display_name="NearPlayer")
    token_b = await _login_and_profile(client, PHONE_B, display_name="FarPlayer")
    await _login_and_profile(client, PHONE_C, display_name="NoCoords")

    from users.models import PlayerProfile
    from sqlalchemy import select

    async def _set_coords(phone: str, lat: float, lng: float) -> None:
        from tests.test_auth import _do_full_login as dfl
        t = await dfl(client, phone)
        me = (await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {t['access_token']}"},
        )).json()["data"]
        uid = me["id"]
        result = await db_session.execute(
            select(PlayerProfile).where(PlayerProfile.user_id == uid)
        )
        profile = result.scalar_one_or_none()
        if profile:
            profile.latitude = lat
            profile.longitude = lng
            await db_session.flush()

    # Mumbai centre ≈ 19.076°N 72.877°E
    await _set_coords(PHONE_A, 19.080, 72.880)    # ~0.6 km away
    await _set_coords(PHONE_B, 28.613, 77.209)    # Delhi — ~1400 km away
    await db_session.commit()

    r = await client.get(
        "/api/v1/discovery/players?lat=19.076&lng=72.877&radius_km=5",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    names = [p["display_name"] for p in data]
    assert "NearPlayer" in names
    assert "FarPlayer" not in names
    # distance_km field is populated
    for p in data:
        assert p["distance_km"] is not None
        assert p["distance_km"] <= 5.0


@pytest.mark.asyncio
async def test_location_requires_all_three_params(client: AsyncClient, db_session: AsyncSession):
    """Partial location params (no radius) fall back to standard search without error."""
    token = await _login_and_profile(client, PHONE_A, display_name="PartialLoc")

    r = await client.get(
        "/api/v1/discovery/players?lat=19.076&lng=72.877",
        headers={"Authorization": f"Bearer {token}"},
    )
    # Should succeed as standard search (no radius_km → no location filter).
    assert r.status_code == 200
    # distance_km should be null since location search wasn't triggered.
    for p in r.json()["data"]:
        assert p["distance_km"] is None
