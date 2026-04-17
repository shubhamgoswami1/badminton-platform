"""
P3 Tournament CRUD tests — 12 required cases.

Uses OTP mock mode and a real PostgreSQL test DB. Each test gets a rolled-back session.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ORG = "+910000000001"
PHONE_OTHER = "+910000000002"


# ── Helpers ───────────────────────────────────────────────────


def _tournament_payload(**overrides) -> dict:
    base = {
        "title": "City Open 2026",
        "description": "A fun tournament",
        "city": "Mumbai",
        "format": "KNOCKOUT",
        "match_format": "BEST_OF_3",
        "play_type": "SINGLES",
        "max_participants": 16,
    }
    base.update(overrides)
    return base


async def _create_tournament(client: AsyncClient, token: str, **overrides) -> dict:
    r = await client.post(
        "/api/v1/tournaments",
        json=_tournament_payload(**overrides),
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 201
    return r.json()["data"]


# ── Test cases ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_create_tournament(client: AsyncClient, db_session: AsyncSession):
    tokens = await _do_full_login(client, PHONE_ORG)
    data = await _create_tournament(client, tokens["access_token"])
    assert data["title"] == "City Open 2026"
    assert data["status"] == "DRAFT"
    assert data["format"] == "KNOCKOUT"
    assert data["bracket_generated"] is False


@pytest.mark.asyncio
async def test_create_tournament_unauthenticated(client: AsyncClient):
    r = await client.post("/api/v1/tournaments", json=_tournament_payload())
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_get_tournament(client: AsyncClient, db_session: AsyncSession):
    tokens = await _do_full_login(client, PHONE_ORG)
    created = await _create_tournament(client, tokens["access_token"])
    tid = created["id"]

    r = await client.get(
        f"/api/v1/tournaments/{tid}",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["id"] == tid


@pytest.mark.asyncio
async def test_get_tournament_not_found(client: AsyncClient, db_session: AsyncSession):
    tokens = await _do_full_login(client, PHONE_ORG)
    r = await client.get(
        "/api/v1/tournaments/00000000-0000-0000-0000-000000000000",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_list_tournaments(client: AsyncClient, db_session: AsyncSession):
    tokens = await _do_full_login(client, PHONE_ORG)
    await _create_tournament(client, tokens["access_token"], title="T1")
    await _create_tournament(client, tokens["access_token"], title="T2")

    r = await client.get(
        "/api/v1/tournaments",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r.status_code == 200
    body = r.json()
    assert "data" in body
    assert body["meta"]["total"] >= 2


@pytest.mark.asyncio
async def test_list_tournaments_filter_city(client: AsyncClient, db_session: AsyncSession):
    tokens = await _do_full_login(client, PHONE_ORG)
    await _create_tournament(client, tokens["access_token"], city="Delhi")
    await _create_tournament(client, tokens["access_token"], city="Pune")

    r = await client.get(
        "/api/v1/tournaments?city=Delhi",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r.status_code == 200
    for t in r.json()["data"]:
        assert t["city"].lower() == "delhi"


@pytest.mark.asyncio
async def test_update_tournament(client: AsyncClient, db_session: AsyncSession):
    tokens = await _do_full_login(client, PHONE_ORG)
    created = await _create_tournament(client, tokens["access_token"])

    r = await client.put(
        f"/api/v1/tournaments/{created['id']}",
        json={"title": "Updated Title"},
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["title"] == "Updated Title"


@pytest.mark.asyncio
async def test_update_tournament_forbidden(client: AsyncClient, db_session: AsyncSession):
    org_tokens = await _do_full_login(client, PHONE_ORG)
    other_tokens = await _do_full_login(client, PHONE_OTHER)
    created = await _create_tournament(client, org_tokens["access_token"])

    r = await client.put(
        f"/api/v1/tournaments/{created['id']}",
        json={"title": "Hacked"},
        headers={"Authorization": f"Bearer {other_tokens['access_token']}"},
    )
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_transition_status_draft_to_registration_open(client: AsyncClient, db_session: AsyncSession):
    tokens = await _do_full_login(client, PHONE_ORG)
    created = await _create_tournament(client, tokens["access_token"])

    r = await client.post(
        f"/api/v1/tournaments/{created['id']}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["status"] == "REGISTRATION_OPEN"


@pytest.mark.asyncio
async def test_transition_status_invalid(client: AsyncClient, db_session: AsyncSession):
    tokens = await _do_full_login(client, PHONE_ORG)
    created = await _create_tournament(client, tokens["access_token"])

    # Cannot jump from DRAFT to IN_PROGRESS
    r = await client.post(
        f"/api/v1/tournaments/{created['id']}/status",
        json={"next_status": "IN_PROGRESS"},
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r.status_code == 409


@pytest.mark.asyncio
async def test_cancel_tournament(client: AsyncClient, db_session: AsyncSession):
    tokens = await _do_full_login(client, PHONE_ORG)
    created = await _create_tournament(client, tokens["access_token"])

    r = await client.delete(
        f"/api/v1/tournaments/{created['id']}",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r.status_code == 200

    # Cancelled tournament should be soft-deleted (not found)
    r2 = await client.get(
        f"/api/v1/tournaments/{created['id']}",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r2.status_code == 404


@pytest.mark.asyncio
async def test_cancel_tournament_forbidden(client: AsyncClient, db_session: AsyncSession):
    org_tokens = await _do_full_login(client, PHONE_ORG)
    other_tokens = await _do_full_login(client, PHONE_OTHER)
    created = await _create_tournament(client, org_tokens["access_token"])

    r = await client.delete(
        f"/api/v1/tournaments/{created['id']}",
        headers={"Authorization": f"Bearer {other_tokens['access_token']}"},
    )
    assert r.status_code == 403
