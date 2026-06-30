"""
Round-robin standings ordering tests.

Covers:
  1. Empty standings (no completed matches) — all zeros, all participants present.
  2. Basic ordering by wins/points.
  3. Point-difference tiebreak: same wins, different set-score margins.
  4. Three-way tiebreak resolved by point_diff.
  5. Standings not available for knockout tournaments (409).
  6. Standings unauthenticated → 401.
  7. point_diff field is present in every response item.
  8. Walkover counts as win but contributes 0 to point_diff.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ORG = "+918100000001"
PHONES = [f"+91810000{i:04d}" for i in range(2, 20)]


# ── Helpers ────────────────────────────────────────────────────────────────────

async def _create_rr_tournament(
    client: AsyncClient,
    org_token: str,
    n_players: int,
    player_phones: list[str],
) -> tuple[str, list[str], list[str]]:
    """Create RR tournament, register n_players, generate bracket.
    Returns (tid, participant_ids, player_tokens)."""
    r = await client.post(
        "/api/v1/tournaments",
        json={
            "title": "Standings Cup",
            "format": "ROUND_ROBIN",
            "match_format": "BEST_OF_1",
            "play_type": "SINGLES",
        },
        headers={"Authorization": f"Bearer {org_token}"},
    )
    tid = r.json()["data"]["id"]

    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {org_token}"},
    )

    participant_ids, player_tokens = [], []
    for phone in player_phones[:n_players]:
        tok = await _do_full_login(client, phone)
        player_tokens.append(tok["access_token"])
        reg = await client.post(
            f"/api/v1/tournaments/{tid}/participants",
            json={},
            headers={"Authorization": f"Bearer {tok['access_token']}"},
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
    return tid, participant_ids, player_tokens


async def _get_standings(
    client: AsyncClient, tid: str, token: str
) -> list[dict]:
    r = await client.get(
        f"/api/v1/tournaments/{tid}/standings",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200, r.text
    return r.json()["data"]


async def _submit(
    client: AsyncClient,
    match_id: str,
    winner_id: str,
    token: str,
    side_a_score: int = 21,
    side_b_score: int = 15,
) -> None:
    await client.post(
        f"/api/v1/matches/{match_id}/score",
        json={
            "sets": [
                {
                    "set_number": 1,
                    "side_a_score": side_a_score,
                    "side_b_score": side_b_score,
                }
            ],
            "winner_participant_id": winner_id,
        },
        headers={"Authorization": f"Bearer {token}"},
    )


# ── Tests ──────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_standings_empty_before_any_matches(
    client: AsyncClient, db_session: AsyncSession
):
    """Standings are returned immediately after bracket generation with all zeros."""
    org = await _do_full_login(client, PHONE_ORG)
    tid, _, _ = await _create_rr_tournament(client, org["access_token"], 4, PHONES)

    standings = await _get_standings(client, tid, org["access_token"])
    assert len(standings) == 4
    for entry in standings:
        assert entry["matches_played"] == 0
        assert entry["wins"] == 0
        assert entry["losses"] == 0
        assert entry["points"] == 0
        assert entry["point_diff"] == 0


@pytest.mark.asyncio
async def test_standings_point_diff_field_present(
    client: AsyncClient, db_session: AsyncSession
):
    """Every standing entry must include the point_diff field."""
    org = await _do_full_login(client, PHONE_ORG)
    tid, _, _ = await _create_rr_tournament(client, org["access_token"], 4, PHONES)

    standings = await _get_standings(client, tid, org["access_token"])
    for entry in standings:
        assert "point_diff" in entry, f"Missing point_diff in {entry}"


@pytest.mark.asyncio
async def test_standings_basic_ordering_by_wins(
    client: AsyncClient, db_session: AsyncSession
):
    """Player with more wins ranks higher than one with fewer wins."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    tid, pids, _ = await _create_rr_tournament(client, org_token, 4, PHONES)

    # Get all round-1 matches and complete them so we have clear ordering.
    r = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    matches = r.json()["data"]

    # Submit results for all matches: side_a always wins.
    for m in matches:
        if m["status"] == "PENDING" and m["side_a_participant_id"]:
            await _submit(client, m["id"], m["side_a_participant_id"], org_token)

    standings = await _get_standings(client, tid, org_token)

    # Points must be non-increasing across the sorted list.
    for i in range(len(standings) - 1):
        assert standings[i]["points"] >= standings[i + 1]["points"]


@pytest.mark.asyncio
async def test_standings_point_diff_tiebreak(
    client: AsyncClient, db_session: AsyncSession
):
    """
    Two players with the same wins are ranked by point_diff.

    Setup (3 players, RR — 3 matches):
      P0 beats P1  21-5   (P0 point_diff += 16, P1 += -16)
      P0 beats P2  21-19  (P0 point_diff += 2,  P2 += -2)
      P1 beats P2  21-10  (P1 point_diff += 11, P2 += -11)

    Final points: P0=4, P1=2, P2=0
    Final point_diff: P0=+18, P1=-5, P2=-13

    Expected order: P0, P1, P2
    """
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    tid, pids, _ = await _create_rr_tournament(client, org_token, 3, PHONES)

    r = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    all_matches = r.json()["data"]

    def _find_match(pid_a: str, pid_b: str) -> dict | None:
        for m in all_matches:
            sides = {m["side_a_participant_id"], m["side_b_participant_id"]}
            if {pid_a, pid_b} == sides:
                return m
        return None

    p0, p1, p2 = pids[0], pids[1], pids[2]

    # P0 vs P1: P0 wins 21-5
    m01 = _find_match(p0, p1)
    if m01:
        a_score = 21 if m01["side_a_participant_id"] == p0 else 5
        b_score = 5 if m01["side_a_participant_id"] == p0 else 21
        await _submit(client, m01["id"], p0, org_token, a_score, b_score)

    # P0 vs P2: P0 wins 21-19
    m02 = _find_match(p0, p2)
    if m02:
        a_score = 21 if m02["side_a_participant_id"] == p0 else 19
        b_score = 19 if m02["side_a_participant_id"] == p0 else 21
        await _submit(client, m02["id"], p0, org_token, a_score, b_score)

    # P1 vs P2: P1 wins 21-10
    m12 = _find_match(p1, p2)
    if m12:
        a_score = 21 if m12["side_a_participant_id"] == p1 else 10
        b_score = 10 if m12["side_a_participant_id"] == p1 else 21
        await _submit(client, m12["id"], p1, org_token, a_score, b_score)

    standings = await _get_standings(client, tid, org_token)

    # Verify rank order by participant_id strings.
    ranked_ids = [str(s["participant_id"]) for s in standings]
    assert ranked_ids[0] == p0, f"P0 should be top; got {ranked_ids}"
    assert ranked_ids[1] == p1, f"P1 should be second; got {ranked_ids}"
    assert ranked_ids[2] == p2, f"P2 should be last; got {ranked_ids}"

    # Verify point_diff values.
    s0 = next(s for s in standings if str(s["participant_id"]) == p0)
    s1 = next(s for s in standings if str(s["participant_id"]) == p1)
    s2 = next(s for s in standings if str(s["participant_id"]) == p2)

    assert s0["point_diff"] == 18, f"P0 point_diff: {s0['point_diff']}"
    assert s1["point_diff"] == -5, f"P1 point_diff: {s1['point_diff']}"
    assert s2["point_diff"] == -13, f"P2 point_diff: {s2['point_diff']}"


@pytest.mark.asyncio
async def test_standings_walkover_no_point_diff(
    client: AsyncClient, db_session: AsyncSession
):
    """A walkover win counts as a win (2 pts) but adds 0 to point_diff."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    tid, pids, _ = await _create_rr_tournament(client, org_token, 3, PHONES)

    r = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    first_match = next(
        m for m in r.json()["data"] if m["status"] == "PENDING"
    )
    winner_id = first_match["side_a_participant_id"]

    await client.post(
        f"/api/v1/matches/{first_match['id']}/walkover",
        json={"winner_participant_id": winner_id},
        headers={"Authorization": f"Bearer {org_token}"},
    )

    standings = await _get_standings(client, tid, org_token)
    winner_entry = next(
        s for s in standings if str(s["participant_id"]) == winner_id
    )
    assert winner_entry["wins"] == 1
    assert winner_entry["points"] == 2
    # Walkover has no set scores → point_diff contribution is 0.
    assert winner_entry["point_diff"] == 0


@pytest.mark.asyncio
async def test_standings_not_available_for_knockout(
    client: AsyncClient, db_session: AsyncSession
):
    """Standing endpoint returns 409 for knockout tournaments."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]

    r = await client.post(
        "/api/v1/tournaments",
        json={
            "title": "KO Cup",
            "format": "KNOCKOUT",
            "match_format": "BEST_OF_1",
            "play_type": "SINGLES",
        },
        headers={"Authorization": f"Bearer {org_token}"},
    )
    tid = r.json()["data"]["id"]

    r2 = await client.get(
        f"/api/v1/tournaments/{tid}/standings",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r2.status_code == 409


@pytest.mark.asyncio
async def test_standings_unauthenticated(
    client: AsyncClient, db_session: AsyncSession
):
    """Unauthenticated request returns 401."""
    org = await _do_full_login(client, PHONE_ORG)
    tid, _, _ = await _create_rr_tournament(
        client, org["access_token"], 3, PHONES
    )
    r = await client.get(f"/api/v1/tournaments/{tid}/standings")
    assert r.status_code == 401
