"""
P9 Training goal tests — 8 required cases.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE = "+917000000001"
PHONE_2 = "+917000000002"


def _goal_payload(**overrides) -> dict:
    base = {"title": "Improve backhand", "description": "Focus on cross-court shots"}
    base.update(overrides)
    return base


@pytest.mark.asyncio
async def test_create_goal(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    r = await client.post("/api/v1/training/goals", json=_goal_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 201
    data = r.json()["data"]
    assert data["title"] == "Improve backhand"
    assert data["status"] == "ACTIVE"


@pytest.mark.asyncio
async def test_list_goals(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    await client.post("/api/v1/training/goals", json=_goal_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})
    await client.post("/api/v1/training/goals", json=_goal_payload(title="Improve serve"), headers={"Authorization": f"Bearer {t['access_token']}"})

    r = await client.get("/api/v1/training/goals", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 200
    assert r.json()["meta"]["total"] >= 2


@pytest.mark.asyncio
async def test_get_goal(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    created = (await client.post("/api/v1/training/goals", json=_goal_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})).json()["data"]

    r = await client.get(f"/api/v1/training/goals/{created['id']}", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 200
    assert r.json()["data"]["id"] == created["id"]


@pytest.mark.asyncio
async def test_update_goal(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    created = (await client.post("/api/v1/training/goals", json=_goal_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})).json()["data"]

    r = await client.put(
        f"/api/v1/training/goals/{created['id']}",
        json={"title": "Updated title"},
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["title"] == "Updated title"


@pytest.mark.asyncio
async def test_mark_goal_achieved(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    created = (await client.post("/api/v1/training/goals", json=_goal_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})).json()["data"]

    r = await client.put(
        f"/api/v1/training/goals/{created['id']}",
        json={"status": "ACHIEVED"},
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["status"] == "ACHIEVED"
    assert data["completed_at"] is not None


@pytest.mark.asyncio
async def test_delete_goal(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    created = (await client.post("/api/v1/training/goals", json=_goal_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})).json()["data"]

    r = await client.delete(f"/api/v1/training/goals/{created['id']}", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 200

    r2 = await client.get(f"/api/v1/training/goals/{created['id']}", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r2.status_code == 404


@pytest.mark.asyncio
async def test_goal_isolation_between_users(client: AsyncClient, db_session: AsyncSession):
    t1 = await _do_full_login(client, PHONE)
    t2 = await _do_full_login(client, PHONE_2)
    created = (await client.post("/api/v1/training/goals", json=_goal_payload(), headers={"Authorization": f"Bearer {t1['access_token']}"})).json()["data"]

    r = await client.get(f"/api/v1/training/goals/{created['id']}", headers={"Authorization": f"Bearer {t2['access_token']}"})
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_list_goals_unauthenticated(client: AsyncClient):
    r = await client.get("/api/v1/training/goals")
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_list_player_goals_returns_target_goals(client: AsyncClient, db_session: AsyncSession):
    t1 = await _do_full_login(client, PHONE)
    t2 = await _do_full_login(client, PHONE_2)

    await client.post("/api/v1/training/goals", json=_goal_payload(title="Player 1 goal"), headers={"Authorization": f"Bearer {t1['access_token']}"})

    # Get user_id of t1 from their own list
    me = (await client.get("/api/v1/training/goals", headers={"Authorization": f"Bearer {t1['access_token']}"})).json()
    user_id = me["data"][0]["user_id"]

    r = await client.get(f"/api/v1/training/goals/player/{user_id}", headers={"Authorization": f"Bearer {t2['access_token']}"})
    assert r.status_code == 200
    items = r.json()["data"]
    assert any(g["title"] == "Player 1 goal" for g in items)


@pytest.mark.asyncio
async def test_list_player_goals_empty_for_new_user(client: AsyncClient, db_session: AsyncSession):
    t1 = await _do_full_login(client, PHONE)
    t2 = await _do_full_login(client, PHONE_2)

    # Get t2's user_id (no goals created)
    me = (await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {t2['access_token']}"})).json()
    user_id = me["data"]["id"]

    r = await client.get(f"/api/v1/training/goals/player/{user_id}", headers={"Authorization": f"Bearer {t1['access_token']}"})
    assert r.status_code == 200
    assert r.json()["meta"]["total"] == 0


@pytest.mark.asyncio
async def test_list_player_goals_unauthenticated(client: AsyncClient, db_session: AsyncSession):
    import uuid
    r = await client.get(f"/api/v1/training/goals/player/{uuid.uuid4()}")
    assert r.status_code == 401
