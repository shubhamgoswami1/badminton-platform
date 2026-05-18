"""
Offline score-sync conflict handling tests.

Conflict response contract (409)
────────────────────────────────
{
  "data": {
    "server_version": <int>,
    "server_updated_at": "<ISO-8601>",
    "server_status": "<PENDING|IN_PROGRESS|COMPLETED|WALKOVER>",
    "sets": [
      {"id": "...", "match_id": "...", "set_number": 1,
       "side_a_score": 21, "side_b_score": 15,
       "submitted_by": "...", "submitted_at": "..."},
      ...
    ]
  },
  "error": {
    "code": "SYNC_CONFLICT",
    "message": "<human-readable>",
    "conflict_type": "STALE_UPDATE | MATCH_COMPLETED"
  }
}

Rules under test
────────────────
1. client_updated_at absent (no prior fetch)      → accepted, no conflict check
2. client_updated_at == server updated_at          → accepted (same version)
3. client_updated_at newer than server updated_at  → accepted (newest wins)
4. client_updated_at older than server updated_at  → 409 STALE_UPDATE
5. update-score on COMPLETED match                 → 409 MATCH_COMPLETED
6. complete on already-COMPLETED, same winner      → 200 (idempotent)
7. complete on already-COMPLETED, different winner → 409 MATCH_COMPLETED
8. complete on WALKOVER                            → 409 MATCH_COMPLETED
"""

from datetime import datetime, timezone, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ORG = "+916000000001"
PHONES = [f"+91600000{i:04d}" for i in range(2, 20)]


# ── Shared setup helper ────────────────────────────────────────────────────────


async def _setup(client: AsyncClient, n: int = 4):
    """Return (org_token, pending_match_dict, participant_ids)."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]

    r = await client.post(
        "/api/v1/tournaments",
        json={"title": "Sync Cup", "format": "KNOCKOUT",
              "match_format": "BEST_OF_3", "play_type": "SINGLES"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    tid = r.json()["data"]["id"]

    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    participant_ids = []
    for i in range(n):
        t = await _do_full_login(client, PHONES[i])
        reg = await client.post(
            f"/api/v1/tournaments/{tid}/participants",
            json={},
            headers={"Authorization": f"Bearer {t['access_token']}"},
        )
        participant_ids.append(reg.json()["data"]["id"])

    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_CLOSED"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    await client.post(
        f"/api/v1/tournaments/{tid}/bracket/generate",
        headers={"Authorization": f"Bearer {org_token}"},
    )

    r = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    matches = r.json()["data"]
    pending = next(m for m in matches if m["status"] == "PENDING" and m["round"] == 1)
    return org_token, pending, participant_ids


def _update_payload(sets=None, client_updated_at=None):
    base = {
        "sets": sets or [
            {"set_number": 1, "side_a_score": 21, "side_b_score": 15},
            {"set_number": 2, "side_a_score": 21, "side_b_score": 18},
        ],
    }
    if client_updated_at is not None:
        base["client_updated_at"] = client_updated_at
    return base


def _complete_payload(winner_id, sets=None, client_updated_at=None):
    base = {"winner_participant_id": winner_id}
    if sets:
        base["sets"] = sets
    if client_updated_at is not None:
        base["client_updated_at"] = client_updated_at
    return base


# ── Rule 1: no client_updated_at → accepted ───────────────────────────────────


@pytest.mark.asyncio
async def test_update_no_timestamp_accepted(
    client: AsyncClient, db_session: AsyncSession
):
    org_token, match, _ = await _setup(client)

    r = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json=_update_payload(),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["status"] == "IN_PROGRESS"
    assert "updated_at" in data


# ── Rule 2 & 3: same or newer client timestamp → accepted ─────────────────────


@pytest.mark.asyncio
async def test_update_exact_timestamp_accepted(
    client: AsyncClient, db_session: AsyncSession
):
    org_token, match, _ = await _setup(client)

    # First update: get server's updated_at.
    r1 = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json=_update_payload(),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    server_updated_at = r1.json()["data"]["updated_at"]

    # Second update with exact same timestamp → accepted.
    r2 = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json=_update_payload(client_updated_at=server_updated_at),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r2.status_code == 200


@pytest.mark.asyncio
async def test_update_newer_client_timestamp_accepted(
    client: AsyncClient, db_session: AsyncSession
):
    org_token, match, _ = await _setup(client)

    r1 = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json=_update_payload(),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    server_updated_at = r1.json()["data"]["updated_at"]

    # Client timestamp slightly in the future (clock skew simulation).
    future_ts = (
        datetime.fromisoformat(server_updated_at) + timedelta(seconds=5)
    ).isoformat()

    r2 = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json=_update_payload(client_updated_at=future_ts),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r2.status_code == 200


# ── Rule 4: stale client timestamp → STALE_UPDATE conflict ────────────────────


@pytest.mark.asyncio
async def test_update_stale_timestamp_rejected(
    client: AsyncClient, db_session: AsyncSession
):
    """
    Scenario: device A and device B both fetch the match.
    Device A saves scores first (server updated_at advances).
    Device B tries to save with the old timestamp → STALE_UPDATE 409.
    """
    org_token, match, _ = await _setup(client)

    # First write (simulates device A).
    r1 = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json=_update_payload(),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r1.status_code == 200

    # Stale timestamp (before the first write).
    stale_ts = datetime(2020, 1, 1, tzinfo=timezone.utc).isoformat()

    # Second write with stale timestamp (simulates device B).
    r2 = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json=_update_payload(client_updated_at=stale_ts),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r2.status_code == 409
    body = r2.json()

    # Validate conflict response contract.
    assert body["error"]["code"] == "SYNC_CONFLICT"
    assert body["error"]["conflict_type"] == "STALE_UPDATE"
    assert body["data"]["server_version"] > 0
    assert body["data"]["server_status"] == "IN_PROGRESS"
    assert "server_updated_at" in body["data"]
    # Client can immediately use the sets to refresh its local state.
    assert isinstance(body["data"]["sets"], list)


# ── Rule 5: update-score on COMPLETED match → MATCH_COMPLETED ─────────────────


@pytest.mark.asyncio
async def test_update_score_on_completed_match_rejected(
    client: AsyncClient, db_session: AsyncSession
):
    org_token, match, _ = await _setup(client)
    winner_id = match["side_a_participant_id"]

    # Complete the match.
    await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json={
            "sets": [{"set_number": 1, "side_a_score": 21, "side_b_score": 15}],
            "winner_participant_id": winner_id,
        },
        headers={"Authorization": f"Bearer {org_token}"},
    )

    # Try to update scores on a completed match.
    r = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json=_update_payload(),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 409
    body = r.json()
    assert body["error"]["code"] == "SYNC_CONFLICT"
    assert body["error"]["conflict_type"] == "MATCH_COMPLETED"
    assert body["data"]["server_status"] == "COMPLETED"
    # Conflict response carries the actual score rows.
    assert isinstance(body["data"]["sets"], list)
    assert len(body["data"]["sets"]) >= 1


# ── Rule 6: complete idempotent — same winner → 200 ───────────────────────────


@pytest.mark.asyncio
async def test_complete_idempotent_same_winner(
    client: AsyncClient, db_session: AsyncSession
):
    org_token, match, _ = await _setup(client)
    winner_id = match["side_a_participant_id"]

    payload = _complete_payload(
        winner_id,
        sets=[{"set_number": 1, "side_a_score": 21, "side_b_score": 15}],
    )
    headers = {"Authorization": f"Bearer {org_token}"}

    r1 = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json=payload,
        headers=headers,
    )
    assert r1.status_code == 200

    # Retry with same winner (network retry simulation).
    r2 = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json=payload,
        headers=headers,
    )
    assert r2.status_code == 200
    assert r2.json()["data"]["status"] == "COMPLETED"
    assert r2.json()["data"]["winner_participant_id"] == winner_id


# ── Rule 7: complete with different winner → MATCH_COMPLETED ──────────────────


@pytest.mark.asyncio
async def test_complete_different_winner_rejected(
    client: AsyncClient, db_session: AsyncSession
):
    org_token, match, _ = await _setup(client)
    winner_a = match["side_a_participant_id"]
    winner_b = match["side_b_participant_id"]

    headers = {"Authorization": f"Bearer {org_token}"}

    # Complete with side A.
    r1 = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json=_complete_payload(winner_a, sets=[
            {"set_number": 1, "side_a_score": 21, "side_b_score": 15}
        ]),
        headers=headers,
    )
    assert r1.status_code == 200

    # Try to complete with side B — conflict.
    r2 = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json=_complete_payload(winner_b, sets=[
            {"set_number": 1, "side_a_score": 15, "side_b_score": 21}
        ]),
        headers=headers,
    )
    assert r2.status_code == 409
    body = r2.json()
    assert body["error"]["code"] == "SYNC_CONFLICT"
    assert body["error"]["conflict_type"] == "MATCH_COMPLETED"
    assert body["data"]["server_status"] == "COMPLETED"


# ── Rule 8: complete on WALKOVER → MATCH_COMPLETED ────────────────────────────


@pytest.mark.asyncio
async def test_complete_on_walkover_rejected(
    client: AsyncClient, db_session: AsyncSession
):
    org_token, match, _ = await _setup(client)
    winner_id = match["side_a_participant_id"]
    headers = {"Authorization": f"Bearer {org_token}"}

    # Record walkover.
    await client.post(
        f"/api/v1/matches/{match['id']}/walkover",
        json={"winner_participant_id": winner_id},
        headers=headers,
    )

    # Try to /complete the walkover match.
    r = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json=_complete_payload(winner_id),
        headers=headers,
    )
    assert r.status_code == 409
    body = r.json()
    assert body["error"]["code"] == "SYNC_CONFLICT"
    assert body["error"]["conflict_type"] == "MATCH_COMPLETED"
    assert body["data"]["server_status"] == "WALKOVER"


# ── updated_at field present in all mutating responses ────────────────────────


@pytest.mark.asyncio
async def test_updated_at_present_in_responses(
    client: AsyncClient, db_session: AsyncSession
):
    org_token, match, _ = await _setup(client)
    headers = {"Authorization": f"Bearer {org_token}"}

    # GET /matches/{id}
    r = await client.get(
        f"/api/v1/matches/{match['id']}",
        headers=headers,
    )
    assert r.status_code == 200
    assert "updated_at" in r.json()["data"]

    # POST /matches/{id}/update-score
    r2 = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json=_update_payload(),
        headers=headers,
    )
    assert r2.status_code == 200
    assert "updated_at" in r2.json()["data"]

    ts_after_update = r2.json()["data"]["updated_at"]
    version_after_update = r2.json()["data"]["version"]

    # POST /matches/{id}/complete
    winner_id = match["side_a_participant_id"]
    r3 = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json=_complete_payload(winner_id),
        headers=headers,
    )
    assert r3.status_code == 200
    ts_after_complete = r3.json()["data"]["updated_at"]
    version_after_complete = r3.json()["data"]["version"]

    # updated_at must advance and version must increment.
    assert ts_after_complete >= ts_after_update
    assert version_after_complete > version_after_update
