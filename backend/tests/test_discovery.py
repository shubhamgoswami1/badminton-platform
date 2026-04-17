"""
P10 Discovery tests — 7 required cases.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE = "+918000000001"
PHONE_2 = "+918000000002"


# ── Helpers ───────────────────────────────────────────────────


async def _create_profile(client: AsyncClient, token: str, **overrides) -> None:
    base = {"display_name": "Test Player", "city": "Mumbai", "skill_level": "INTERMEDIATE"}
    base.update(overrides)
    await client.put("/api/v1/users/me/profile", json=base, headers={"Authorization": f"Bearer {token}"})


# ── Test cases ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_discover_players_returns_list(client: AsyncClient, db_session: AsyncSession):
    t1 = await _do_full_login(client, PHONE)
    await _create_profile(client, t1["access_token"], display_name="Player One")

    r = await client.get("/api/v1/discovery/players", headers={"Authorization": f"Bearer {t1['access_token']}"})
    assert r.status_code == 200
    assert r.json()["meta"]["total"] >= 1


@pytest.mark.asyncio
async def test_discover_players_filter_city(client: AsyncClient, db_session: AsyncSession):
    t1 = await _do_full_login(client, PHONE)
    t2 = await _do_full_login(client, PHONE_2)
    await _create_profile(client, t1["access_token"], city="Delhi")
    await _create_profile(client, t2["access_token"], city="Hyderabad")

    r = await client.get("/api/v1/discovery/players?city=Delhi", headers={"Authorization": f"Bearer {t1['access_token']}"})
    assert r.status_code == 200
    for p in r.json()["data"]:
        assert p["city"].lower() == "delhi"


@pytest.mark.asyncio
async def test_discover_tournaments(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)

    await client.post(
        "/api/v1/tournaments",
        json={"title": "Discovery Cup", "format": "KNOCKOUT", "match_format": "BEST_OF_3", "play_type": "SINGLES", "city": "Chennai"},
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )

    r = await client.get("/api/v1/discovery/tournaments", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 200
    assert r.json()["meta"]["total"] >= 1


@pytest.mark.asyncio
async def test_discover_tournaments_filter_city(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)

    await client.post(
        "/api/v1/tournaments",
        json={"title": "Kolkata Cup", "format": "KNOCKOUT", "match_format": "BEST_OF_3", "play_type": "SINGLES", "city": "Kolkata"},
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )

    r = await client.get("/api/v1/discovery/tournaments?city=Kolkata", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 200
    for tournament in r.json()["data"]:
        assert tournament["city"].lower() == "kolkata"


@pytest.mark.asyncio
async def test_submit_venue(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)

    r = await client.post(
        "/api/v1/discovery/venues",
        json={"name": "City Sports Complex", "city": "Bangalore", "court_count": 8},
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )
    assert r.status_code == 201
    assert r.json()["data"]["name"] == "City Sports Complex"
    assert r.json()["data"]["court_count"] == 8


@pytest.mark.asyncio
async def test_list_venues(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)

    await client.post("/api/v1/discovery/venues", json={"name": "Arena A", "city": "Pune"}, headers={"Authorization": f"Bearer {t['access_token']}"})
    await client.post("/api/v1/discovery/venues", json={"name": "Arena B", "city": "Pune"}, headers={"Authorization": f"Bearer {t['access_token']}"})

    r = await client.get("/api/v1/discovery/venues?city=Pune", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 200
    assert r.json()["meta"]["total"] >= 2


@pytest.mark.asyncio
async def test_discovery_unauthenticated(client: AsyncClient):
    r = await client.get("/api/v1/discovery/players")
    assert r.status_code == 401
