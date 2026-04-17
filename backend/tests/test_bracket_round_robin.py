"""
P7 Round-robin bracket tests — 7 required cases.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ORG = "+914000000001"
PHONES = [f"+91400000{i:04d}" for i in range(2, 20)]


# ── Helpers ───────────────────────────────────────────────────


async def _setup_rr_tournament(client: AsyncClient, n: int) -> tuple[str, str]:
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]

    r = await client.post(
        "/api/v1/tournaments",
        json={"title": "RR Cup", "format": "ROUND_ROBIN", "match_format": "BEST_OF_1", "play_type": "SINGLES"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    tid = r.json()["data"]["id"]

    await client.post(f"/api/v1/tournaments/{tid}/status", json={"next_status": "REGISTRATION_OPEN"}, headers={"Authorization": f"Bearer {org_token}"})

    for i in range(n):
        t = await _do_full_login(client, PHONES[i])
        await client.post(f"/api/v1/tournaments/{tid}/participants", json={}, headers={"Authorization": f"Bearer {t['access_token']}"})

    await client.post(f"/api/v1/tournaments/{tid}/status", json={"next_status": "REGISTRATION_CLOSED"}, headers={"Authorization": f"Bearer {org_token}"})

    return tid, org_token


# ── Test cases ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_rr_bracket_4_players(client: AsyncClient, db_session: AsyncSession):
    tid, org_token = await _setup_rr_tournament(client, 4)

    r = await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 201
    # 4 players → 4C2 = 6 matches
    assert r.json()["data"]["matches_created"] == 6


@pytest.mark.asyncio
async def test_rr_bracket_5_players(client: AsyncClient, db_session: AsyncSession):
    tid, org_token = await _setup_rr_tournament(client, 5)

    r = await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 201
    # 5 players → 5C2 = 10 matches
    assert r.json()["data"]["matches_created"] == 10


@pytest.mark.asyncio
async def test_rr_bracket_no_duplicate_matches(client: AsyncClient, db_session: AsyncSession):
    tid, org_token = await _setup_rr_tournament(client, 4)

    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})
    r = await client.get(f"/api/v1/tournaments/{tid}/matches", headers={"Authorization": f"Bearer {org_token}"})
    matches = r.json()["data"]

    pairs = set()
    for m in matches:
        a = m["side_a_participant_id"]
        b = m["side_b_participant_id"]
        pair = frozenset([a, b])
        assert pair not in pairs, f"Duplicate match: {a} vs {b}"
        pairs.add(pair)


@pytest.mark.asyncio
async def test_rr_each_player_plays_n_minus_1_matches(client: AsyncClient, db_session: AsyncSession):
    n = 4
    tid, org_token = await _setup_rr_tournament(client, n)

    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})
    r = await client.get(f"/api/v1/tournaments/{tid}/matches", headers={"Authorization": f"Bearer {org_token}"})
    matches = r.json()["data"]

    appearances: dict[str, int] = {}
    for m in matches:
        for side in ("side_a_participant_id", "side_b_participant_id"):
            pid = m[side]
            if pid:
                appearances[pid] = appearances.get(pid, 0) + 1

    for pid, count in appearances.items():
        assert count == n - 1, f"Participant {pid} played {count} matches, expected {n - 1}"


@pytest.mark.asyncio
async def test_rr_standings_endpoint(client: AsyncClient, db_session: AsyncSession):
    tid, org_token = await _setup_rr_tournament(client, 4)
    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})

    r = await client.get(f"/api/v1/tournaments/{tid}/standings", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 200
    standings = r.json()["data"]
    assert len(standings) == 4


@pytest.mark.asyncio
async def test_standings_not_available_for_knockout(client: AsyncClient, db_session: AsyncSession):
    from tests.test_bracket_knockout import _setup_tournament_with_participants
    tid, org_token, _ = await _setup_tournament_with_participants(client, 4)
    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})

    r = await client.get(f"/api/v1/tournaments/{tid}/standings", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 409


@pytest.mark.asyncio
async def test_rr_bracket_rounds_coverage(client: AsyncClient, db_session: AsyncSession):
    """For N=4, circle method yields 3 rounds."""
    tid, org_token = await _setup_rr_tournament(client, 4)

    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})
    r = await client.get(f"/api/v1/tournaments/{tid}/matches", headers={"Authorization": f"Bearer {org_token}"})
    matches = r.json()["data"]

    rounds = {m["round"] for m in matches}
    assert rounds == {1, 2, 3}
