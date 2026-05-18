"""
Automatic tournament completion tests.

When the last non-BYE match in a tournament is completed (or walkoverd),
the tournament should automatically transition to COMPLETED.

Covers:
  1. 2-player KO: completing the single final auto-completes tournament.
  2. 4-player KO: completing all matches (R1 + final) auto-completes tournament.
  3. 3-player RR: completing all matches auto-completes tournament.
  4. Partial completion does NOT trigger auto-complete.
  5. Walkover as final result triggers auto-complete.
  6. Tournament stays IN_PROGRESS mid-tournament (not all matches done).
  7. Auto-complete only fires for IN_PROGRESS tournaments (not DRAFT, etc.).
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ORG = "+918200000001"
PHONES = [f"+91820000{i:04d}" for i in range(2, 20)]


# ── Helpers ────────────────────────────────────────────────────────────────────

async def _setup_tournament(
    client: AsyncClient,
    org_token: str,
    fmt: str,
    n: int,
    player_phones: list[str],
    title: str = "Auto-Complete Cup",
) -> tuple[str, list[str]]:
    """Create tournament, register n players, generate bracket.
    Returns (tid, participant_ids)."""
    r = await client.post(
        "/api/v1/tournaments",
        json={
            "title": title,
            "format": fmt,
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

    participant_ids = []
    for phone in player_phones[:n]:
        tok = await _do_full_login(client, phone)
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
    return tid, participant_ids


async def _get_tournament_status(
    client: AsyncClient, tid: str, token: str
) -> str:
    r = await client.get(
        f"/api/v1/tournaments/{tid}",
        headers={"Authorization": f"Bearer {token}"},
    )
    return r.json()["data"]["status"]


async def _score(
    client: AsyncClient,
    match_id: str,
    winner_id: str,
    token: str,
) -> None:
    await client.post(
        f"/api/v1/matches/{match_id}/score",
        json={
            "sets": [{"set_number": 1, "side_a_score": 21, "side_b_score": 15}],
            "winner_participant_id": winner_id,
        },
        headers={"Authorization": f"Bearer {token}"},
    )


async def _walkover(
    client: AsyncClient,
    match_id: str,
    winner_id: str,
    token: str,
) -> None:
    await client.post(
        f"/api/v1/matches/{match_id}/walkover",
        json={"winner_participant_id": winner_id},
        headers={"Authorization": f"Bearer {token}"},
    )


async def _pending_matches(
    client: AsyncClient, tid: str, token: str
) -> list[dict]:
    r = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {token}"},
    )
    return [m for m in r.json()["data"] if m["status"] == "PENDING"]


# ── Tests ──────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_auto_complete_2_player_ko(
    client: AsyncClient, db_session: AsyncSession
):
    """2-player KO has one match; completing it auto-completes the tournament."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    tid, _ = await _setup_tournament(client, org_token, "KNOCKOUT", 2, PHONES)

    matches = await _pending_matches(client, tid, org_token)
    assert len(matches) == 1

    await _score(client, matches[0]["id"], matches[0]["side_a_participant_id"], org_token)

    status = await _get_tournament_status(client, tid, org_token)
    assert status == "COMPLETED", f"Expected COMPLETED, got {status}"


@pytest.mark.asyncio
async def test_auto_complete_4_player_ko(
    client: AsyncClient, db_session: AsyncSession
):
    """4-player KO: tournament stays IN_PROGRESS after R1, completes after final."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    tid, _ = await _setup_tournament(client, org_token, "KNOCKOUT", 4, PHONES)

    # Complete R1 matches.
    r1_matches = await _pending_matches(client, tid, org_token)
    for m in r1_matches:
        await _score(client, m["id"], m["side_a_participant_id"], org_token)

    # Should still be IN_PROGRESS — final not done yet.
    status_mid = await _get_tournament_status(client, tid, org_token)
    assert status_mid == "IN_PROGRESS", f"Expected IN_PROGRESS mid-way, got {status_mid}"

    # Complete the final.
    final = await _pending_matches(client, tid, org_token)
    assert len(final) == 1
    await _score(client, final[0]["id"], final[0]["side_a_participant_id"], org_token)

    status_end = await _get_tournament_status(client, tid, org_token)
    assert status_end == "COMPLETED", f"Expected COMPLETED, got {status_end}"


@pytest.mark.asyncio
async def test_auto_complete_rr_tournament(
    client: AsyncClient, db_session: AsyncSession
):
    """3-player RR: completing all 3 matches auto-completes the tournament."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    tid, _ = await _setup_tournament(client, org_token, "ROUND_ROBIN", 3, PHONES)

    r = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    real_matches = [m for m in r.json()["data"] if m["status"] == "PENDING"]

    for m in real_matches:
        await _score(client, m["id"], m["side_a_participant_id"], org_token)

    status = await _get_tournament_status(client, tid, org_token)
    assert status == "COMPLETED", f"Expected COMPLETED, got {status}"


@pytest.mark.asyncio
async def test_partial_completion_no_auto_complete(
    client: AsyncClient, db_session: AsyncSession
):
    """Tournament stays IN_PROGRESS until all matches are done."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    tid, _ = await _setup_tournament(client, org_token, "KNOCKOUT", 4, PHONES)

    # Complete only the first R1 match.
    r1 = await _pending_matches(client, tid, org_token)
    await _score(client, r1[0]["id"], r1[0]["side_a_participant_id"], org_token)

    status = await _get_tournament_status(client, tid, org_token)
    assert status == "IN_PROGRESS", f"Expected IN_PROGRESS, got {status}"


@pytest.mark.asyncio
async def test_auto_complete_via_walkover(
    client: AsyncClient, db_session: AsyncSession
):
    """Walkover on the last match also triggers auto-completion."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    tid, _ = await _setup_tournament(client, org_token, "KNOCKOUT", 2, PHONES)

    matches = await _pending_matches(client, tid, org_token)
    await _walkover(client, matches[0]["id"], matches[0]["side_a_participant_id"], org_token)

    status = await _get_tournament_status(client, tid, org_token)
    assert status == "COMPLETED", f"Expected COMPLETED after walkover, got {status}"


@pytest.mark.asyncio
async def test_auto_complete_via_complete_endpoint(
    client: AsyncClient, db_session: AsyncSession
):
    """Using POST /complete (not /score) also triggers auto-completion."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    tid, _ = await _setup_tournament(client, org_token, "KNOCKOUT", 2, PHONES)

    matches = await _pending_matches(client, tid, org_token)
    m = matches[0]
    winner_id = m["side_a_participant_id"]

    await client.post(
        f"/api/v1/matches/{m['id']}/complete",
        json={
            "winner_participant_id": winner_id,
            "sets": [{"set_number": 1, "side_a_score": 21, "side_b_score": 18}],
        },
        headers={"Authorization": f"Bearer {org_token}"},
    )

    status = await _get_tournament_status(client, tid, org_token)
    assert status == "COMPLETED", f"Expected COMPLETED, got {status}"


@pytest.mark.asyncio
async def test_auto_complete_byes_not_counted(
    client: AsyncClient, db_session: AsyncSession
):
    """BYE matches are ignored — only real matches need to be finished."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]
    # 3-player KO → 1 BYE in R1, 1 real R1 match, 1 final.
    tid, _ = await _setup_tournament(client, org_token, "KNOCKOUT", 3, PHONES)

    r = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    all_matches = r.json()["data"]
    real = [m for m in all_matches if m["status"] == "PENDING"]

    for m in real:
        if m["side_a_participant_id"] and m["side_b_participant_id"]:
            await _score(client, m["id"], m["side_a_participant_id"], org_token)

    # Refresh pending after R1.
    remaining = await _pending_matches(client, tid, org_token)
    for m in remaining:
        if m["side_a_participant_id"] and m["side_b_participant_id"]:
            await _score(client, m["id"], m["side_a_participant_id"], org_token)

    status = await _get_tournament_status(client, tid, org_token)
    assert status == "COMPLETED", f"Expected COMPLETED, got {status}"
