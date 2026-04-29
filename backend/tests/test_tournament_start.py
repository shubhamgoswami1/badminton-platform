"""
Tournament start (POST /tournaments/{id}/start) tests.

Covers:
- Happy path: 4 participants, REGISTRATION_CLOSED → IN_PROGRESS + bracket generated
- Auto-close: start from REGISTRATION_OPEN auto-transitions through REGISTRATION_CLOSED
- Insufficient participants (< 4) → 409
- Wrong status (DRAFT) → 409
- Non-organiser → 403
- Already started (IN_PROGRESS) → 409
- Teams scaffold: create and list teams
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

# Use distinct phone ranges to avoid collisions with other test modules.
PHONE_ORG = "+919100000001"
PHONE_P1 = "+919100000002"
PHONE_P2 = "+919100000003"
PHONE_P3 = "+919100000004"
PHONE_P4 = "+919100000005"
PHONE_P5 = "+919100000006"
PHONE_STRANGER = "+919100000099"


# ── Helpers ───────────────────────────────────────────────────


async def _create_tournament(client: AsyncClient, token: str, **overrides) -> str:
    body = {
        "title": "Start Test Cup",
        "format": "KNOCKOUT",
        "match_format": "BEST_OF_3",
        "play_type": "SINGLES",
        **overrides,
    }
    r = await client.post(
        "/api/v1/tournaments",
        json=body,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 201, r.text
    return r.json()["data"]["id"]


async def _open_registration(client: AsyncClient, tid: str, token: str) -> None:
    r = await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200, r.text


async def _close_registration(client: AsyncClient, tid: str, token: str) -> None:
    r = await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_CLOSED"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200, r.text


async def _register(client: AsyncClient, tid: str, token: str) -> str:
    r = await client.post(
        f"/api/v1/tournaments/{tid}/participants",
        json={},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 201, r.text
    return r.json()["data"]["id"]


async def _setup_closed_tournament_with_participants(
    client: AsyncClient,
    org_token: str,
    participant_tokens: list[str],
) -> str:
    """Create tournament, open registration, register N participants, close registration."""
    tid = await _create_tournament(client, org_token)
    await _open_registration(client, tid, org_token)
    for tok in participant_tokens:
        await _register(client, tid, tok)
    await _close_registration(client, tid, org_token)
    return tid


# ── Tests ─────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_start_tournament_happy_path(client: AsyncClient, db_session: AsyncSession):
    """4 participants + REGISTRATION_CLOSED → IN_PROGRESS, bracket generated."""
    org = await _do_full_login(client, PHONE_ORG)
    tokens = [
        (await _do_full_login(client, ph))["access_token"]
        for ph in [PHONE_P1, PHONE_P2, PHONE_P3, PHONE_P4]
    ]
    tid = await _setup_closed_tournament_with_participants(
        client, org["access_token"], tokens
    )

    r = await client.post(
        f"/api/v1/tournaments/{tid}/start",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["status"] == "IN_PROGRESS"
    assert data["bracket_generated"] is True


@pytest.mark.asyncio
async def test_start_tournament_auto_closes_registration(client: AsyncClient, db_session: AsyncSession):
    """Starting from REGISTRATION_OPEN auto-closes registration then starts."""
    org = await _do_full_login(client, PHONE_ORG)
    tokens = [
        (await _do_full_login(client, ph))["access_token"]
        for ph in [PHONE_P1, PHONE_P2, PHONE_P3, PHONE_P4]
    ]
    tid = await _create_tournament(client, org["access_token"])
    await _open_registration(client, tid, org["access_token"])
    for tok in tokens:
        await _register(client, tid, tok)
    # Do NOT close registration — /start should handle it.

    r = await client.post(
        f"/api/v1/tournaments/{tid}/start",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["status"] == "IN_PROGRESS"
    assert data["bracket_generated"] is True


@pytest.mark.asyncio
async def test_start_tournament_insufficient_participants(client: AsyncClient, db_session: AsyncSession):
    """Fewer than 4 participants → 409 Conflict."""
    org = await _do_full_login(client, PHONE_ORG)
    tokens = [
        (await _do_full_login(client, ph))["access_token"]
        for ph in [PHONE_P1, PHONE_P2, PHONE_P3]  # only 3
    ]
    tid = await _setup_closed_tournament_with_participants(
        client, org["access_token"], tokens
    )

    r = await client.post(
        f"/api/v1/tournaments/{tid}/start",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 409, r.text


@pytest.mark.asyncio
async def test_start_tournament_wrong_status_draft(client: AsyncClient, db_session: AsyncSession):
    """Tournament in DRAFT cannot be started directly → 409."""
    org = await _do_full_login(client, PHONE_ORG)
    tid = await _create_tournament(client, org["access_token"])
    # Stay in DRAFT — do not open registration.

    r = await client.post(
        f"/api/v1/tournaments/{tid}/start",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 409, r.text


@pytest.mark.asyncio
async def test_start_tournament_non_organiser_forbidden(client: AsyncClient, db_session: AsyncSession):
    """Non-organiser (even a registered participant) cannot start the tournament → 403."""
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    tokens = [
        (await _do_full_login(client, ph))["access_token"]
        for ph in [PHONE_P1, PHONE_P2, PHONE_P3, PHONE_P4]
    ]
    tid = await _setup_closed_tournament_with_participants(
        client, org["access_token"], tokens
    )

    r = await client.post(
        f"/api/v1/tournaments/{tid}/start",
        headers={"Authorization": f"Bearer {p1['access_token']}"},
    )
    assert r.status_code == 403, r.text


@pytest.mark.asyncio
async def test_start_tournament_already_started(client: AsyncClient, db_session: AsyncSession):
    """Calling /start on an already IN_PROGRESS tournament → 409."""
    org = await _do_full_login(client, PHONE_ORG)
    tokens = [
        (await _do_full_login(client, ph))["access_token"]
        for ph in [PHONE_P1, PHONE_P2, PHONE_P3, PHONE_P4]
    ]
    tid = await _setup_closed_tournament_with_participants(
        client, org["access_token"], tokens
    )

    # First start — should succeed.
    r1 = await client.post(
        f"/api/v1/tournaments/{tid}/start",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r1.status_code == 200, r1.text

    # Second start — should fail.
    r2 = await client.post(
        f"/api/v1/tournaments/{tid}/start",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r2.status_code == 409, r2.text


@pytest.mark.asyncio
async def test_start_unauthenticated(client: AsyncClient, db_session: AsyncSession):
    """Unauthenticated request → 401."""
    org = await _do_full_login(client, PHONE_ORG)
    tid = await _create_tournament(client, org["access_token"])

    r = await client.post(f"/api/v1/tournaments/{tid}/start")
    assert r.status_code == 401, r.text


# ── Teams scaffold tests ──────────────────────────────────────


@pytest.mark.asyncio
async def test_create_and_list_team(client: AsyncClient, db_session: AsyncSession):
    """Organiser can pair two participants as a team; team appears in list."""
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    p2 = await _do_full_login(client, PHONE_P2)

    tid = await _create_tournament(client, org["access_token"], play_type="DOUBLES")
    await _open_registration(client, tid, org["access_token"])

    pid1 = await _register(client, tid, p1["access_token"])
    pid2 = await _register(client, tid, p2["access_token"])

    # Create team
    r = await client.post(
        f"/api/v1/tournaments/{tid}/teams",
        json={"participant_a_id": pid1, "participant_b_id": pid2, "name": "Dream Team"},
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 201, r.text
    team_data = r.json()["data"]
    assert team_data["participant_a_id"] == pid1
    assert team_data["participant_b_id"] == pid2
    assert team_data["name"] == "Dream Team"

    # List teams
    r2 = await client.get(
        f"/api/v1/tournaments/{tid}/teams",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r2.status_code == 200, r2.text
    assert len(r2.json()["data"]) == 1


@pytest.mark.asyncio
async def test_create_team_non_organiser_forbidden(client: AsyncClient, db_session: AsyncSession):
    """Only the organiser can create teams → 403 for others."""
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    p2 = await _do_full_login(client, PHONE_P2)

    tid = await _create_tournament(client, org["access_token"], play_type="DOUBLES")
    await _open_registration(client, tid, org["access_token"])

    pid1 = await _register(client, tid, p1["access_token"])
    pid2 = await _register(client, tid, p2["access_token"])

    r = await client.post(
        f"/api/v1/tournaments/{tid}/teams",
        json={"participant_a_id": pid1, "participant_b_id": pid2},
        headers={"Authorization": f"Bearer {p1['access_token']}"},
    )
    assert r.status_code == 403, r.text
