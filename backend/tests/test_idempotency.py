"""
Idempotency key tests for POST /matches/{id}/score — P6 Fix #6.

Three cases:
1. First request succeeds and completes the match.
2. Retry with the same key returns the cached response (200) without error.
3. Different key on a completed match returns 409 (SYNC_CONFLICT).
"""

import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login
from tests.test_scores import _setup_match, _score_payload

PHONE_IDEM = "+915099900001"


@pytest.mark.asyncio
async def test_idempotency_first_request_succeeds(client: AsyncClient, db_session: AsyncSession):
    """First call with an Idempotency-Key completes the match normally."""
    _, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]
    key = str(uuid.uuid4())

    r = await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner),
        headers={"Authorization": f"Bearer {org_token}", "Idempotency-Key": key},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["status"] == "COMPLETED"
    assert data["winner_participant_id"] == winner


@pytest.mark.asyncio
async def test_idempotency_retry_returns_cached_response(client: AsyncClient, db_session: AsyncSession):
    """Repeated request with same key returns the cached 200 without re-processing."""
    _, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]
    key = str(uuid.uuid4())

    headers = {"Authorization": f"Bearer {org_token}", "Idempotency-Key": key}

    # First request
    r1 = await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner),
        headers=headers,
    )
    assert r1.status_code == 200

    # Second request with same key — should get cached response, not 409
    r2 = await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner),
        headers=headers,
    )
    assert r2.status_code == 200
    assert r2.json()["data"]["winner_participant_id"] == r1.json()["data"]["winner_participant_id"]


@pytest.mark.asyncio
async def test_idempotency_different_key_on_completed_match_is_conflict(
    client: AsyncClient, db_session: AsyncSession
):
    """Using a fresh key on an already-completed match returns 409 SYNC_CONFLICT."""
    _, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]

    # Complete the match with key A
    r1 = await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner),
        headers={
            "Authorization": f"Bearer {org_token}",
            "Idempotency-Key": str(uuid.uuid4()),
        },
    )
    assert r1.status_code == 200

    # Retry with a different key — server detects already-completed match
    r2 = await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner),
        headers={
            "Authorization": f"Bearer {org_token}",
            "Idempotency-Key": str(uuid.uuid4()),
        },
    )
    assert r2.status_code == 409
    assert r2.json()["error"]["code"] == "SYNC_CONFLICT"
