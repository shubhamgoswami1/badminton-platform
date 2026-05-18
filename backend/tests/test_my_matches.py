"""
GET /matches/my — aggregation tests.

Covers:
  1. Returns empty list when user has no matches.
  2. Returns matches across a single tournament.
  3. Filters by status=PENDING correctly.
  4. Filters by comma-separated statuses (PENDING,IN_PROGRESS).
  5. Does NOT return matches the user has no involvement in.
  6. Returns matches from multiple tournaments (deduplication check).
  7. Returns 401 when unauthenticated.
  8. Completed matches are returned when status=COMPLETED.
  9. Response shape includes tournament_title and organiser_id.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ORG = "+918000000001"
PHONES = [f"+91800000{i:04d}" for i in range(2, 20)]


# ── Helpers ────────────────────────────────────────────────────────────────────

async def _setup_singles_ko(
    client: AsyncClient,
    org_phone: str,
    player_phones: list[str],
    title: str = "My-Matches Cup",
) -> tuple[str, str, list[str], list[str]]:
    """
    Create a SINGLES KNOCKOUT tournament, register players, generate bracket.
    Returns (tid, org_token, participant_ids, player_tokens).
    """
    org = await _do_full_login(client, org_phone)
    org_token = org["access_token"]

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
    tid = r.json()["data"]["id"]

    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {org_token}"},
    )

    participant_ids, player_tokens = [], []
    for phone in player_phones:
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
    return tid, org_token, participant_ids, player_tokens


def _score_payload(winner_id: str) -> dict:
    return {
        "sets": [{"set_number": 1, "side_a_score": 21, "side_b_score": 15}],
        "winner_participant_id": winner_id,
    }


# ── Tests ──────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_my_matches_empty_for_new_user(client: AsyncClient, db_session: AsyncSession):
    """User with no registered participations gets an empty list."""
    user = await _do_full_login(client, "+918099990001")
    r = await client.get(
        "/api/v1/matches/my",
        headers={"Authorization": f"Bearer {user['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"] == []


@pytest.mark.asyncio
async def test_my_matches_returns_assigned_matches(
    client: AsyncClient, db_session: AsyncSession
):
    """Player sees their match(es) after bracket is generated."""
    _, _, _, player_tokens = await _setup_singles_ko(
        client, PHONE_ORG, PHONES[:4]
    )

    r = await client.get(
        "/api/v1/matches/my",
        headers={"Authorization": f"Bearer {player_tokens[0]}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert len(data) >= 1  # Player 0 is in at least one R1 match


@pytest.mark.asyncio
async def test_my_matches_response_shape(
    client: AsyncClient, db_session: AsyncSession
):
    """Response items include all required fields including tournament context."""
    _, _, _, player_tokens = await _setup_singles_ko(
        client, PHONE_ORG, PHONES[:4], title="Shape Test Cup"
    )

    r = await client.get(
        "/api/v1/matches/my",
        headers={"Authorization": f"Bearer {player_tokens[0]}"},
    )
    assert r.status_code == 200
    item = r.json()["data"][0]

    required_fields = {
        "id", "tournament_id", "round", "match_number",
        "status", "tournament_title", "organiser_id",
        "elo_applied", "version",
    }
    assert required_fields.issubset(item.keys()), (
        f"Missing: {required_fields - item.keys()}"
    )
    assert item["tournament_title"] == "Shape Test Cup"
    assert item["status"] == "PENDING"


@pytest.mark.asyncio
async def test_my_matches_filter_by_status_pending(
    client: AsyncClient, db_session: AsyncSession
):
    """?status=PENDING returns only pending matches."""
    tid, org_token, _, player_tokens = await _setup_singles_ko(
        client, PHONE_ORG, PHONES[:4]
    )

    # Complete one match to create a COMPLETED record.
    r_all = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    r1_match = next(
        m for m in r_all.json()["data"]
        if m["round"] == 1 and m["status"] == "PENDING"
    )
    await client.post(
        f"/api/v1/matches/{r1_match['id']}/score",
        json=_score_payload(r1_match["side_a_participant_id"]),
        headers={"Authorization": f"Bearer {org_token}"},
    )

    r = await client.get(
        "/api/v1/matches/my?status=PENDING",
        headers={"Authorization": f"Bearer {player_tokens[0]}"},
    )
    assert r.status_code == 200
    for item in r.json()["data"]:
        assert item["status"] == "PENDING"


@pytest.mark.asyncio
async def test_my_matches_filter_multi_status(
    client: AsyncClient, db_session: AsyncSession
):
    """?status=PENDING,IN_PROGRESS returns only those statuses."""
    _, org_token, _, player_tokens = await _setup_singles_ko(
        client, PHONE_ORG, PHONES[:4]
    )

    r = await client.get(
        "/api/v1/matches/my?status=PENDING,IN_PROGRESS",
        headers={"Authorization": f"Bearer {player_tokens[0]}"},
    )
    assert r.status_code == 200
    for item in r.json()["data"]:
        assert item["status"] in {"PENDING", "IN_PROGRESS"}


@pytest.mark.asyncio
async def test_my_matches_filter_completed(
    client: AsyncClient, db_session: AsyncSession
):
    """?status=COMPLETED surfaces only completed matches."""
    tid, org_token, _, player_tokens = await _setup_singles_ko(
        client, PHONE_ORG, PHONES[:4]
    )

    # Initially no completed matches.
    r0 = await client.get(
        "/api/v1/matches/my?status=COMPLETED",
        headers={"Authorization": f"Bearer {player_tokens[0]}"},
    )
    assert r0.json()["data"] == []

    # Complete a match.
    r_all = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    r1 = next(m for m in r_all.json()["data"] if m["round"] == 1 and m["status"] == "PENDING")
    await client.post(
        f"/api/v1/matches/{r1['id']}/score",
        json=_score_payload(r1["side_a_participant_id"]),
        headers={"Authorization": f"Bearer {org_token}"},
    )

    r1_after = await client.get(
        "/api/v1/matches/my?status=COMPLETED",
        headers={"Authorization": f"Bearer {player_tokens[0]}"},
    )
    # Player 0 in this match now sees it as completed.
    completed = r1_after.json()["data"]
    assert any(m["status"] == "COMPLETED" for m in completed)


@pytest.mark.asyncio
async def test_my_matches_excludes_uninvolved_players(
    client: AsyncClient, db_session: AsyncSession
):
    """A user who joined a different tournament does not see these matches."""
    # Set up tournament A with players 0-3.
    await _setup_singles_ko(client, PHONE_ORG, PHONES[:4], title="Tournament A")

    # Player who is NOT in tournament A.
    outsider = await _do_full_login(client, "+918099990002")

    r = await client.get(
        "/api/v1/matches/my",
        headers={"Authorization": f"Bearer {outsider['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["data"] == []


@pytest.mark.asyncio
async def test_my_matches_across_multiple_tournaments(
    client: AsyncClient, db_session: AsyncSession
):
    """Player registered in two tournaments sees matches from both."""
    player_phone = PHONES[0]

    # Tournament 1
    await _setup_singles_ko(
        client, PHONE_ORG, PHONES[:4], title="Multi-T Cup 1"
    )
    # Tournament 2 with the same player
    await _setup_singles_ko(
        client, PHONE_ORG, PHONES[:4], title="Multi-T Cup 2"
    )

    player_tok = (await _do_full_login(client, player_phone))["access_token"]
    r = await client.get(
        "/api/v1/matches/my",
        headers={"Authorization": f"Bearer {player_tok}"},
    )
    assert r.status_code == 200
    titles = {m["tournament_title"] for m in r.json()["data"]}
    # Player appears in both tournaments — both titles should be present.
    assert "Multi-T Cup 1" in titles
    assert "Multi-T Cup 2" in titles


@pytest.mark.asyncio
async def test_my_matches_unauthenticated(client: AsyncClient, db_session: AsyncSession):
    """Unauthenticated request returns 401."""
    r = await client.get("/api/v1/matches/my")
    assert r.status_code == 401
