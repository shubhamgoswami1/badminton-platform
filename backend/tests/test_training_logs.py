"""
Training log tests — create/list basics, intensity validation, player log view.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE = "+916000000001"
PHONE_2 = "+916000000002"


def _log_payload(**overrides) -> dict:
    base = {"session_type": "PRACTICE", "duration_minutes": 60, "notes": "Good session"}
    base.update(overrides)
    return base


@pytest.mark.asyncio
async def test_create_training_log(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    r = await client.post("/api/v1/training/logs", json=_log_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 201
    data = r.json()["data"]
    assert data["session_type"] == "PRACTICE"
    assert data["duration_minutes"] == 60


@pytest.mark.asyncio
async def test_list_training_logs(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    await client.post("/api/v1/training/logs", json=_log_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})
    await client.post("/api/v1/training/logs", json=_log_payload(session_type="FITNESS"), headers={"Authorization": f"Bearer {t['access_token']}"})

    r = await client.get("/api/v1/training/logs", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 200
    assert r.json()["meta"]["total"] >= 2


@pytest.mark.asyncio
async def test_get_training_log(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    created = (await client.post("/api/v1/training/logs", json=_log_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})).json()["data"]

    r = await client.get(f"/api/v1/training/logs/{created['id']}", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 200
    assert r.json()["data"]["id"] == created["id"]


@pytest.mark.asyncio
async def test_update_training_log(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    created = (await client.post("/api/v1/training/logs", json=_log_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})).json()["data"]

    r = await client.put(
        f"/api/v1/training/logs/{created['id']}",
        json={"duration_minutes": 90},
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["duration_minutes"] == 90


@pytest.mark.asyncio
async def test_delete_training_log(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    created = (await client.post("/api/v1/training/logs", json=_log_payload(), headers={"Authorization": f"Bearer {t['access_token']}"})).json()["data"]

    r = await client.delete(f"/api/v1/training/logs/{created['id']}", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 200

    r2 = await client.get(f"/api/v1/training/logs/{created['id']}", headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r2.status_code == 404


@pytest.mark.asyncio
async def test_log_isolation_between_users(client: AsyncClient, db_session: AsyncSession):
    t1 = await _do_full_login(client, PHONE)
    t2 = await _do_full_login(client, PHONE_2)
    created = (await client.post("/api/v1/training/logs", json=_log_payload(), headers={"Authorization": f"Bearer {t1['access_token']}"})).json()["data"]

    r = await client.get(f"/api/v1/training/logs/{created['id']}", headers={"Authorization": f"Bearer {t2['access_token']}"})
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_create_log_invalid_duration(client: AsyncClient, db_session: AsyncSession):
    t = await _do_full_login(client, PHONE)
    r = await client.post("/api/v1/training/logs", json=_log_payload(duration_minutes=-5), headers={"Authorization": f"Bearer {t['access_token']}"})
    assert r.status_code == 422


@pytest.mark.asyncio
async def test_list_logs_unauthenticated(client: AsyncClient):
    r = await client.get("/api/v1/training/logs")
    assert r.status_code == 401


# ── Intensity field ───────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_create_log_with_intensity(client: AsyncClient, db_session: AsyncSession):
    """Log created with intensity is stored and returned correctly."""
    t = await _do_full_login(client, PHONE)
    r = await client.post(
        "/api/v1/training/logs",
        json=_log_payload(intensity="HIGH"),
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )
    assert r.status_code == 201
    data = r.json()["data"]
    assert data["intensity"] == "HIGH"


@pytest.mark.asyncio
async def test_create_log_invalid_intensity(client: AsyncClient, db_session: AsyncSession):
    """Unknown intensity value is rejected with 422."""
    t = await _do_full_login(client, PHONE)
    r = await client.post(
        "/api/v1/training/logs",
        json=_log_payload(intensity="EXTREME"),
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )
    assert r.status_code == 422


@pytest.mark.asyncio
async def test_update_log_intensity(client: AsyncClient, db_session: AsyncSession):
    """Intensity can be set or changed via PUT."""
    t = await _do_full_login(client, PHONE)
    created = (
        await client.post(
            "/api/v1/training/logs",
            json=_log_payload(),
            headers={"Authorization": f"Bearer {t['access_token']}"},
        )
    ).json()["data"]

    r = await client.put(
        f"/api/v1/training/logs/{created['id']}",
        json={"intensity": "MEDIUM"},
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["intensity"] == "MEDIUM"


@pytest.mark.asyncio
async def test_intensity_absent_when_not_set(client: AsyncClient, db_session: AsyncSession):
    """When intensity is not supplied it is null in the response."""
    t = await _do_full_login(client, PHONE)
    r = await client.post(
        "/api/v1/training/logs",
        json=_log_payload(),
        headers={"Authorization": f"Bearer {t['access_token']}"},
    )
    assert r.status_code == 201
    assert r.json()["data"]["intensity"] is None


# ── Player log view (GET /training/logs/player/{user_id}) ─────────────────────

@pytest.mark.asyncio
async def test_list_player_logs_returns_target_user_logs(
    client: AsyncClient, db_session: AsyncSession
):
    """Authenticated user can fetch another player's training logs."""
    t1 = await _do_full_login(client, PHONE)
    t2 = await _do_full_login(client, PHONE_2)

    # t1 creates two logs.
    await client.post(
        "/api/v1/training/logs",
        json=_log_payload(session_type="DRILL"),
        headers={"Authorization": f"Bearer {t1['access_token']}"},
    )
    await client.post(
        "/api/v1/training/logs",
        json=_log_payload(session_type="FITNESS"),
        headers={"Authorization": f"Bearer {t1['access_token']}"},
    )

    # t1's user_id is in the /me response.
    me = (
        await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {t1['access_token']}"},
        )
    ).json()["data"]
    t1_user_id = me["id"]

    # t2 fetches t1's logs via the player endpoint.
    r = await client.get(
        f"/api/v1/training/logs/player/{t1_user_id}",
        headers={"Authorization": f"Bearer {t2['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["meta"]["total"] >= 2


@pytest.mark.asyncio
async def test_list_player_logs_empty_for_new_user(
    client: AsyncClient, db_session: AsyncSession
):
    """Player endpoint returns empty list when the target has no logs."""
    t1 = await _do_full_login(client, PHONE)
    t2 = await _do_full_login(client, PHONE_2)

    me2 = (
        await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {t2['access_token']}"},
        )
    ).json()["data"]

    r = await client.get(
        f"/api/v1/training/logs/player/{me2['id']}",
        headers={"Authorization": f"Bearer {t1['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["meta"]["total"] == 0


@pytest.mark.asyncio
async def test_list_player_logs_unauthenticated(client: AsyncClient, db_session: AsyncSession):
    """Player log endpoint requires authentication."""
    import uuid as _uuid
    r = await client.get(f"/api/v1/training/logs/player/{_uuid.uuid4()}")
    assert r.status_code == 401
