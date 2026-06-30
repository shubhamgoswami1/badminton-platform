"""
Admin module tests.

Covers
──────
1. Non-admin user gets 403 on every admin endpoint
2. Unauthenticated request gets 401
3. ban-user: bans the target; banned user gets 403 on protected endpoints
4. ban-user: idempotent — banning already-banned user succeeds
5. ban-user: admin cannot ban themselves → 409
6. unban-user: lifts ban; user regains access
7. delete-tournament: soft-deletes; no longer visible via public endpoints
8. delete-tournament: rejected (409) if any match is IN_PROGRESS
9. delete-tournament: rejected (404) if already deleted
10. GET /admin/logs: returns paginated log entries for each action
11. GET /admin/logs: ?action= filter works
"""

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ADMIN = "+910000000001"
PHONE_USER = "+910000000002"
PHONE_USER2 = "+910000000003"
PHONE_ORG = "+910000000004"


# ── Fixture helpers ───────────────────────────────────────────────────────────


async def _make_admin(db: AsyncSession, phone: str) -> dict:
    """Login as phone and promote the resulting user to admin in DB."""
    from users.models import User
    from sqlalchemy import select

    # Ensure the user row exists via normal login.
    from httpx import AsyncClient as _AC
    # We need a client to create the user — use the app directly.
    from main import app
    from httpx import ASGITransport
    from database import get_db

    async def _override():
        yield db

    app.dependency_overrides[get_db] = _override
    async with _AC(transport=ASGITransport(app=app), base_url="http://test") as tmp:
        tokens = await _do_full_login(tmp, phone)
    app.dependency_overrides.clear()

    # Promote to admin.
    result = await db.execute(
        select(User).where(User.phone_number == phone)
    )
    user = result.scalar_one()
    user.is_admin = True
    await db.commit()
    await db.refresh(user)
    return tokens


async def _create_tournament(
    client: AsyncClient, org_token: str, *, title: str = "Admin Test Cup"
) -> str:
    r = await client.post(
        "/api/v1/tournaments",
        json={
            "title": title,
            "format": "KNOCKOUT",
            "match_format": "BEST_OF_1",
            "play_type": "SINGLES",
        },
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200, r.text
    return r.json()["data"]["id"]


async def _advance_to_in_progress(
    client: AsyncClient, org_token: str, tid: str, player_phones: list[str]
) -> None:
    """Register players, close registration, generate bracket, IN_PROGRESS."""
    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    for phone in player_phones:
        t = await _do_full_login(client, phone)
        await client.post(
            f"/api/v1/tournaments/{tid}/participants",
            json={},
            headers={"Authorization": f"Bearer {t['access_token']}"},
        )
    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_CLOSED"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    await client.post(
        f"/api/v1/tournaments/{tid}/bracket/generate",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "IN_PROGRESS"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    # Put one match IN_PROGRESS by submitting a partial score update.
    r = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    matches = [m for m in r.json()["data"] if m["status"] == "PENDING"]
    if matches:
        match_id = matches[0]["id"]
        await client.post(
            f"/api/v1/matches/{match_id}/update-score",
            json={"sets": [{"set_number": 1, "side_a_score": 15, "side_b_score": 10}]},
            headers={"Authorization": f"Bearer {org_token}"},
        )


# ── 1 & 2: Authorization checks ───────────────────────────────────────────────


@pytest.mark.asyncio
async def test_admin_endpoints_require_auth(client: AsyncClient, db_session: AsyncSession):
    endpoints = [
        ("POST", "/api/v1/admin/ban-user"),
        ("POST", "/api/v1/admin/unban-user"),
        ("POST", "/api/v1/admin/delete-tournament"),
        ("GET", "/api/v1/admin/logs"),
    ]
    for method, url in endpoints:
        r = await client.request(method, url, json={})
        assert r.status_code == 401, f"{method} {url} expected 401, got {r.status_code}"


@pytest.mark.asyncio
async def test_admin_endpoints_require_admin_role(
    client: AsyncClient, db_session: AsyncSession
):
    tokens = await _do_full_login(client, PHONE_USER)
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    endpoints = [
        ("POST", "/api/v1/admin/ban-user", {"user_id": "00000000-0000-0000-0000-000000000001"}),
        ("POST", "/api/v1/admin/unban-user", {"user_id": "00000000-0000-0000-0000-000000000001"}),
        ("POST", "/api/v1/admin/delete-tournament", {"tournament_id": "00000000-0000-0000-0000-000000000001"}),
        ("GET", "/api/v1/admin/logs", {}),
    ]
    for method, url, body in endpoints:
        r = await client.request(method, url, json=body, headers=headers)
        assert r.status_code == 403, f"{method} {url} expected 403, got {r.status_code}"


# ── 3: Ban user → banned user loses access ────────────────────────────────────


@pytest.mark.asyncio
async def test_ban_user_blocks_access(client: AsyncClient, db_session: AsyncSession):
    admin_tokens = await _make_admin(db_session, PHONE_ADMIN)
    user_tokens = await _do_full_login(client, PHONE_USER)

    from users.models import User
    from sqlalchemy import select

    result = await db_session.execute(
        select(User).where(User.phone_number == PHONE_USER)
    )
    target_user_id = str(result.scalar_one().id)

    # Confirm access is currently working.
    r = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {user_tokens['access_token']}"},
    )
    assert r.status_code == 200

    # Ban the user.
    r = await client.post(
        "/api/v1/admin/ban-user",
        json={"user_id": target_user_id, "notes": "test ban"},
        headers={"Authorization": f"Bearer {admin_tokens['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["is_banned"] is True

    # Reload the DB session so the updated row is visible.
    await db_session.rollback()

    # Banned user is now blocked.
    r = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {user_tokens['access_token']}"},
    )
    assert r.status_code == 403


# ── 4: Banning already-banned user is idempotent ─────────────────────────────


@pytest.mark.asyncio
async def test_ban_user_idempotent(client: AsyncClient, db_session: AsyncSession):
    admin_tokens = await _make_admin(db_session, PHONE_ADMIN)
    user_tokens = await _do_full_login(client, PHONE_USER2)

    from users.models import User
    from sqlalchemy import select

    result = await db_session.execute(
        select(User).where(User.phone_number == PHONE_USER2)
    )
    target_id = str(result.scalar_one().id)

    for _ in range(2):
        r = await client.post(
            "/api/v1/admin/ban-user",
            json={"user_id": target_id},
            headers={"Authorization": f"Bearer {admin_tokens['access_token']}"},
        )
        assert r.status_code == 200
        assert r.json()["data"]["is_banned"] is True


# ── 5: Admin cannot ban themselves ────────────────────────────────────────────


@pytest.mark.asyncio
async def test_admin_cannot_ban_self(client: AsyncClient, db_session: AsyncSession):
    admin_tokens = await _make_admin(db_session, PHONE_ADMIN)

    from users.models import User
    from sqlalchemy import select

    result = await db_session.execute(
        select(User).where(User.phone_number == PHONE_ADMIN)
    )
    admin_id = str(result.scalar_one().id)

    r = await client.post(
        "/api/v1/admin/ban-user",
        json={"user_id": admin_id},
        headers={"Authorization": f"Bearer {admin_tokens['access_token']}"},
    )
    assert r.status_code == 409


# ── 6: Unban user → access restored ─────────────────────────────────────────


@pytest.mark.asyncio
async def test_unban_user_restores_access(client: AsyncClient, db_session: AsyncSession):
    admin_tokens = await _make_admin(db_session, PHONE_ADMIN)
    user_tokens = await _do_full_login(client, PHONE_USER)

    from users.models import User
    from sqlalchemy import select

    result = await db_session.execute(
        select(User).where(User.phone_number == PHONE_USER)
    )
    user = result.scalar_one()
    user.is_banned = True
    await db_session.commit()

    # Unban.
    r = await client.post(
        "/api/v1/admin/unban-user",
        json={"user_id": str(user.id), "notes": "reinstated"},
        headers={"Authorization": f"Bearer {admin_tokens['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["is_banned"] is False

    await db_session.rollback()

    # Access restored.
    r = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {user_tokens['access_token']}"},
    )
    assert r.status_code == 200


# ── 7: Delete tournament → soft-deleted, invisible via public endpoints ───────


@pytest.mark.asyncio
async def test_delete_tournament_soft_deletes(
    client: AsyncClient, db_session: AsyncSession
):
    admin_tokens = await _make_admin(db_session, PHONE_ADMIN)
    org_tokens = await _do_full_login(client, PHONE_ORG)
    tid = await _create_tournament(client, org_tokens["access_token"])

    r = await client.post(
        "/api/v1/admin/delete-tournament",
        json={"tournament_id": tid, "notes": "spam tournament"},
        headers={"Authorization": f"Bearer {admin_tokens['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["deleted_at"] is not None

    # Not visible via public listing.
    r = await client.get("/api/v1/tournaments")
    ids = [t["id"] for t in r.json()["data"]]
    assert tid not in ids


# ── 8: Delete tournament rejected if match IN_PROGRESS ────────────────────────


@pytest.mark.asyncio
async def test_delete_tournament_blocked_if_in_progress(
    client: AsyncClient, db_session: AsyncSession
):
    admin_tokens = await _make_admin(db_session, PHONE_ADMIN)
    org_tokens = await _do_full_login(client, PHONE_ORG)
    tid = await _create_tournament(client, org_tokens["access_token"], title="Live Cup")

    await _advance_to_in_progress(
        client,
        org_tokens["access_token"],
        tid,
        [f"+9199990{i:05d}" for i in range(2)],
    )

    r = await client.post(
        "/api/v1/admin/delete-tournament",
        json={"tournament_id": tid},
        headers={"Authorization": f"Bearer {admin_tokens['access_token']}"},
    )
    assert r.status_code == 409


# ── 9: Delete already-deleted tournament → 404 ────────────────────────────────


@pytest.mark.asyncio
async def test_delete_already_deleted_tournament_404(
    client: AsyncClient, db_session: AsyncSession
):
    admin_tokens = await _make_admin(db_session, PHONE_ADMIN)
    org_tokens = await _do_full_login(client, PHONE_ORG)
    tid = await _create_tournament(client, org_tokens["access_token"])

    headers = {"Authorization": f"Bearer {admin_tokens['access_token']}"}
    await client.post(
        "/api/v1/admin/delete-tournament",
        json={"tournament_id": tid},
        headers=headers,
    )

    r = await client.post(
        "/api/v1/admin/delete-tournament",
        json={"tournament_id": tid},
        headers=headers,
    )
    assert r.status_code == 404


# ── 10 & 11: GET /admin/logs ──────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_admin_logs_recorded_and_filterable(
    client: AsyncClient, db_session: AsyncSession
):
    admin_tokens = await _make_admin(db_session, PHONE_ADMIN)
    user_tokens = await _do_full_login(client, PHONE_USER)
    org_tokens = await _do_full_login(client, PHONE_ORG)

    from users.models import User
    from sqlalchemy import select

    result = await db_session.execute(
        select(User).where(User.phone_number == PHONE_USER)
    )
    target_id = str(result.scalar_one().id)
    headers = {"Authorization": f"Bearer {admin_tokens['access_token']}"}

    # Perform two actions.
    await client.post(
        "/api/v1/admin/ban-user",
        json={"user_id": target_id},
        headers=headers,
    )
    await client.post(
        "/api/v1/admin/unban-user",
        json={"user_id": target_id},
        headers=headers,
    )

    # Logs endpoint returns entries.
    r = await client.get("/api/v1/admin/logs", headers=headers)
    assert r.status_code == 200
    body = r.json()
    assert body["meta"]["total"] >= 2
    actions = {log["action"] for log in body["data"]}
    assert "BAN_USER" in actions
    assert "UNBAN_USER" in actions

    # Filter by action.
    r = await client.get(
        "/api/v1/admin/logs?action=BAN_USER", headers=headers
    )
    assert r.status_code == 200
    assert all(log["action"] == "BAN_USER" for log in r.json()["data"])
