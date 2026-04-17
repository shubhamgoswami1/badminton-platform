"""
P4 Participant registration tests — 13 required cases.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ORG = "+911000000001"
PHONE_P1 = "+911000000002"
PHONE_P2 = "+911000000003"
PHONE_P3 = "+911000000004"


# ── Helpers ───────────────────────────────────────────────────


async def _setup_open_tournament(client: AsyncClient, org_token: str) -> str:
    """Create a tournament and open registration. Returns tournament id."""
    r = await client.post(
        "/api/v1/tournaments",
        json={
            "title": "Test Cup",
            "format": "KNOCKOUT",
            "match_format": "BEST_OF_3",
            "play_type": "SINGLES",
            "max_participants": 8,
        },
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 201
    tid = r.json()["data"]["id"]

    r2 = await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r2.status_code == 200
    return tid


async def _register(client: AsyncClient, tid: str, token: str, **body) -> dict:
    r = await client.post(
        f"/api/v1/tournaments/{tid}/participants",
        json=body,
        headers={"Authorization": f"Bearer {token}"},
    )
    return r


# ── Test cases ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_register_participant(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    tid = await _setup_open_tournament(client, org["access_token"])

    r = await _register(client, tid, p1["access_token"])
    assert r.status_code == 201
    assert r.json()["data"]["status"] == "REGISTERED"


@pytest.mark.asyncio
async def test_register_duplicate_rejected(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    tid = await _setup_open_tournament(client, org["access_token"])

    await _register(client, tid, p1["access_token"])
    r = await _register(client, tid, p1["access_token"])
    assert r.status_code == 409


@pytest.mark.asyncio
async def test_organiser_cannot_register(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    tid = await _setup_open_tournament(client, org["access_token"])

    r = await _register(client, tid, org["access_token"])
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_register_when_closed_rejected(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)

    # Tournament in DRAFT (not open)
    r = await client.post(
        "/api/v1/tournaments",
        json={"title": "Closed Cup", "format": "KNOCKOUT", "match_format": "BEST_OF_3", "play_type": "SINGLES"},
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    tid = r.json()["data"]["id"]

    r2 = await _register(client, tid, p1["access_token"])
    assert r2.status_code == 409


@pytest.mark.asyncio
async def test_register_tournament_full(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    tid = await _setup_open_tournament(client, org["access_token"])

    phones = [f"+9120000000{i:02d}" for i in range(8)]
    for ph in phones:
        t = await _do_full_login(client, ph)
        await _register(client, tid, t["access_token"])

    overflow_phone = "+912000000099"
    overflow = await _do_full_login(client, overflow_phone)
    r = await _register(client, tid, overflow["access_token"])
    assert r.status_code == 409


@pytest.mark.asyncio
async def test_list_participants(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    p2 = await _do_full_login(client, PHONE_P2)
    tid = await _setup_open_tournament(client, org["access_token"])

    await _register(client, tid, p1["access_token"])
    await _register(client, tid, p2["access_token"])

    r = await client.get(
        f"/api/v1/tournaments/{tid}/participants",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["meta"]["total"] == 2


@pytest.mark.asyncio
async def test_withdraw_participant(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    tid = await _setup_open_tournament(client, org["access_token"])

    reg = await _register(client, tid, p1["access_token"])
    pid = reg.json()["data"]["id"]

    r = await client.delete(
        f"/api/v1/tournaments/{tid}/participants/{pid}",
        headers={"Authorization": f"Bearer {p1['access_token']}"},
    )
    assert r.status_code == 200


@pytest.mark.asyncio
async def test_withdraw_other_participant_forbidden(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    p2 = await _do_full_login(client, PHONE_P2)
    tid = await _setup_open_tournament(client, org["access_token"])

    reg = await _register(client, tid, p1["access_token"])
    pid = reg.json()["data"]["id"]

    r = await client.delete(
        f"/api/v1/tournaments/{tid}/participants/{pid}",
        headers={"Authorization": f"Bearer {p2['access_token']}"},
    )
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_set_seed_order(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    p2 = await _do_full_login(client, PHONE_P2)
    tid = await _setup_open_tournament(client, org["access_token"])

    r1 = await _register(client, tid, p1["access_token"])
    r2 = await _register(client, tid, p2["access_token"])
    pid1 = r1.json()["data"]["id"]
    pid2 = r2.json()["data"]["id"]

    r = await client.put(
        f"/api/v1/tournaments/{tid}/participants/seed-order",
        json={"ordered_participant_ids": [pid2, pid1]},
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    by_id = {p["id"]: p for p in data}
    assert by_id[pid2]["seed_order"] == 1
    assert by_id[pid1]["seed_order"] == 2


@pytest.mark.asyncio
async def test_set_seed_order_forbidden(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    tid = await _setup_open_tournament(client, org["access_token"])

    r1 = await _register(client, tid, p1["access_token"])
    pid1 = r1.json()["data"]["id"]

    r = await client.put(
        f"/api/v1/tournaments/{tid}/participants/seed-order",
        json={"ordered_participant_ids": [pid1]},
        headers={"Authorization": f"Bearer {p1['access_token']}"},
    )
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_register_doubles_with_partner(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)

    # Create doubles tournament
    r = await client.post(
        "/api/v1/tournaments",
        json={"title": "Doubles Cup", "format": "KNOCKOUT", "match_format": "BEST_OF_3", "play_type": "DOUBLES"},
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    tid = r.json()["data"]["id"]
    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )

    # Find partner user_id by logging in and getting profile
    p2_tokens = await _do_full_login(client, PHONE_P2)
    me_r = await client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {p2_tokens['access_token']}"})
    partner_user_id = me_r.json()["data"]["id"]

    r = await _register(client, tid, p1["access_token"], partner_user_id=partner_user_id)
    assert r.status_code == 201
    assert r.json()["data"]["partner_user_id"] == partner_user_id


@pytest.mark.asyncio
async def test_register_partner_not_found(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    p1 = await _do_full_login(client, PHONE_P1)
    tid = await _setup_open_tournament(client, org["access_token"])

    r = await _register(client, tid, p1["access_token"], partner_user_id="00000000-0000-0000-0000-000000000000")
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_list_participants_unauthenticated(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    tid = await _setup_open_tournament(client, org["access_token"])

    r = await client.get(f"/api/v1/tournaments/{tid}/participants")
    assert r.status_code == 401
