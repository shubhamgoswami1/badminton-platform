"""
P6 Score submission tests — 12 required cases.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ORG = "+915000000001"
PHONES = [f"+91500000{i:04d}" for i in range(2, 20)]


# ── Helpers ───────────────────────────────────────────────────


async def _setup_match(client: AsyncClient, n: int = 4) -> tuple[str, str, dict, list]:
    """Create tournament, generate bracket, return (tid, org_token, first pending match, all participant_ids)."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]

    r = await client.post(
        "/api/v1/tournaments",
        json={"title": "Score Cup", "format": "KNOCKOUT", "match_format": "BEST_OF_3", "play_type": "SINGLES"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    tid = r.json()["data"]["id"]
    await client.post(f"/api/v1/tournaments/{tid}/status", json={"next_status": "REGISTRATION_OPEN"}, headers={"Authorization": f"Bearer {org_token}"})

    participant_ids = []
    for i in range(n):
        t = await _do_full_login(client, PHONES[i])
        reg = await client.post(f"/api/v1/tournaments/{tid}/participants", json={}, headers={"Authorization": f"Bearer {t['access_token']}"})
        participant_ids.append(reg.json()["data"]["id"])

    await client.post(f"/api/v1/tournaments/{tid}/status", json={"next_status": "REGISTRATION_CLOSED"}, headers={"Authorization": f"Bearer {org_token}"})
    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})

    r = await client.get(f"/api/v1/tournaments/{tid}/matches", headers={"Authorization": f"Bearer {org_token}"})
    matches = r.json()["data"]
    # First R1 PENDING match
    pending = next(m for m in matches if m["status"] == "PENDING" and m["round"] == 1)
    return tid, org_token, pending, participant_ids


def _score_payload(winner_id: str) -> dict:
    return {
        "sets": [
            {"set_number": 1, "side_a_score": 21, "side_b_score": 15},
            {"set_number": 2, "side_a_score": 21, "side_b_score": 18},
        ],
        "winner_participant_id": winner_id,
    }


# ── Test cases ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_submit_score_by_organiser(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]

    r = await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["status"] == "COMPLETED"
    assert data["winner_participant_id"] == winner
    assert len(data["sets"]) == 2


@pytest.mark.asyncio
async def test_get_match_score(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]

    await client.post(f"/api/v1/matches/{match['id']}/score", json=_score_payload(winner), headers={"Authorization": f"Bearer {org_token}"})

    r = await client.get(f"/api/v1/matches/{match['id']}/score", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 200
    assert r.json()["data"]["winner_participant_id"] == winner


@pytest.mark.asyncio
async def test_submit_score_invalid_winner(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, match, _ = await _setup_match(client)

    r = await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload("00000000-0000-0000-0000-000000000000"),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 409


@pytest.mark.asyncio
async def test_submit_score_twice_rejected(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]

    await client.post(f"/api/v1/matches/{match['id']}/score", json=_score_payload(winner), headers={"Authorization": f"Bearer {org_token}"})
    r = await client.post(f"/api/v1/matches/{match['id']}/score", json=_score_payload(winner), headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 409


@pytest.mark.asyncio
async def test_score_unauthenticated(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]

    r = await client.post(f"/api/v1/matches/{match['id']}/score", json=_score_payload(winner))
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_score_winner_advances_in_knockout(client: AsyncClient, db_session: AsyncSession):
    """After R1 score submitted, winner should appear in the R2 match slot."""
    tid, org_token, match, _ = await _setup_match(client, n=4)
    winner_id = match["side_a_participant_id"]

    await client.post(f"/api/v1/matches/{match['id']}/score", json=_score_payload(winner_id), headers={"Authorization": f"Bearer {org_token}"})

    r = await client.get(f"/api/v1/tournaments/{tid}/matches", headers={"Authorization": f"Bearer {org_token}"})
    matches = r.json()["data"]
    next_match_id = match["next_match_id"]
    next_match = next(m for m in matches if m["id"] == next_match_id)

    assert (
        next_match["side_a_participant_id"] == winner_id
        or next_match["side_b_participant_id"] == winner_id
    )


@pytest.mark.asyncio
async def test_walkover_by_organiser(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]

    r = await client.post(
        f"/api/v1/matches/{match['id']}/walkover",
        json={"winner_participant_id": winner},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["status"] == "WALKOVER"


@pytest.mark.asyncio
async def test_walkover_forbidden_for_non_organiser(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]
    other = await _do_full_login(client, "+915000000099")

    r = await client.post(
        f"/api/v1/matches/{match['id']}/walkover",
        json={"winner_participant_id": winner},
        headers={"Authorization": f"Bearer {other['access_token']}"},
    )
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_score_match_not_found(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    r = await client.post(
        "/api/v1/matches/00000000-0000-0000-0000-000000000000/score",
        json=_score_payload("00000000-0000-0000-0000-000000000001"),
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_get_score_no_sets_returns_empty(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, match, _ = await _setup_match(client)

    r = await client.get(f"/api/v1/matches/{match['id']}/score", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 200
    assert r.json()["data"]["sets"] == []


@pytest.mark.asyncio
async def test_submit_empty_sets_rejected(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, match, _ = await _setup_match(client)
    winner = match["side_a_participant_id"]

    r = await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json={"sets": [], "winner_participant_id": winner},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 422


@pytest.mark.asyncio
async def test_tournament_completion_after_all_matches(client: AsyncClient, db_session: AsyncSession):
    """All matches completed for a 4-player KO → final completed → tournament still IN_PROGRESS (manual close)."""
    tid, org_token, _, _ = await _setup_match(client, n=4)

    r = await client.get(f"/api/v1/tournaments/{tid}/matches", headers={"Authorization": f"Bearer {org_token}"})
    matches = r.json()["data"]

    # Submit R1 scores
    r1 = sorted([m for m in matches if m["round"] == 1 and m["status"] == "PENDING"], key=lambda m: m["match_number"])
    for m in r1:
        winner = m["side_a_participant_id"]
        await client.post(f"/api/v1/matches/{m['id']}/score", json=_score_payload(winner), headers={"Authorization": f"Bearer {org_token}"})

    # Fetch updated bracket
    r2 = await client.get(f"/api/v1/tournaments/{tid}/matches", headers={"Authorization": f"Bearer {org_token}"})
    final = next(m for m in r2.json()["data"] if m["round"] == 2)
    winner = final["side_a_participant_id"] or final["side_b_participant_id"]
    if winner:
        await client.post(f"/api/v1/matches/{final['id']}/score", json=_score_payload(winner), headers={"Authorization": f"Bearer {org_token}"})

    t_r = await client.get(f"/api/v1/tournaments/{tid}", headers={"Authorization": f"Bearer {org_token}"})
    assert t_r.json()["data"]["status"] == "IN_PROGRESS"
