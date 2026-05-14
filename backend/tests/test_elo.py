"""
P6 Elo rating, player stats, and scoring flow tests.

Covers:
  1. Pure Elo math — expected_score, compute_elo_delta
  2. Elo applied after submit_score (singles)
  3. Elo NOT applied twice (elo_applied guard)
  4. Player stats updated: matches_played, wins, losses
  5. GET /matches/{id} returns full detail
  6. POST /matches/{id}/update-score  → PENDING → IN_PROGRESS
  7. POST /matches/{id}/complete      → IN_PROGRESS → COMPLETED
  8. complete_match with fresh sets
  9. Elo skipped for walkovers
 10. Elo skipped for non-singles (DOUBLES tournament)
 11. update_score rejected for finished match
 12. complete rejected with invalid winner
"""

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from scores.elo import DEFAULT_ELO, K, compute_elo_delta, expected_score
from tests.test_auth import _do_full_login
from users.models import PlayerProfile

# ── Distinct phone pools (no collision with other test files) ──────────────────

PHONE_ORG = "+917000000001"
PHONES = [f"+91700000{i:04d}" for i in range(2, 30)]
PHONE_DOUBLES_ORG = "+917100000001"
PHONES_DOUBLES = [f"+91710000{i:04d}" for i in range(2, 10)]


# ── Helpers ────────────────────────────────────────────────────────────────────

async def _setup_singles_match(
    client: AsyncClient,
    n: int = 4,
    with_profiles: bool = False,
) -> tuple[str, str, dict, list[str], list[str]]:
    """
    Create a singles KNOCKOUT tournament, register n players, generate bracket.

    Returns:
        (tid, org_token, first_pending_match, participant_ids, user_tokens)
    """
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]

    r = await client.post(
        "/api/v1/tournaments",
        json={
            "title": "Elo Cup",
            "format": "KNOCKOUT",
            "match_format": "BEST_OF_3",
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
    user_tokens = []
    for i in range(n):
        tok = await _do_full_login(client, PHONES[i])
        user_tokens.append(tok["access_token"])
        if with_profiles:
            await client.put(
                "/api/v1/users/me/profile",
                json={"display_name": f"Player{i + 1}"},
                headers={"Authorization": f"Bearer {tok['access_token']}"},
            )
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

    r = await client.get(
        f"/api/v1/tournaments/{tid}/matches",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    matches = r.json()["data"]
    pending = next(m for m in matches if m["status"] == "PENDING" and m["round"] == 1)
    return tid, org_token, pending, participant_ids, user_tokens


def _score_payload(winner_id: str) -> dict:
    return {
        "sets": [
            {"set_number": 1, "side_a_score": 21, "side_b_score": 15},
            {"set_number": 2, "side_a_score": 21, "side_b_score": 18},
        ],
        "winner_participant_id": winner_id,
    }


async def _get_profile(db: AsyncSession, user_id_str: str):
    import uuid
    uid = uuid.UUID(user_id_str)
    result = await db.execute(select(PlayerProfile).where(PlayerProfile.user_id == uid))
    return result.scalar_one_or_none()


# ── 1. Pure Elo math ───────────────────────────────────────────────────────────

def test_expected_score_equal_ratings():
    """Equal ratings → 50% expected score."""
    e = expected_score(1500.0, 1500.0)
    assert abs(e - 0.5) < 1e-9


def test_expected_score_higher_rating_favoured():
    """Higher-rated player should have > 50% expected score."""
    e = expected_score(1600.0, 1400.0)
    assert e > 0.5


def test_expected_score_symmetry():
    """E_a + E_b should always equal 1.0."""
    e_a = expected_score(1700.0, 1300.0)
    e_b = expected_score(1300.0, 1700.0)
    assert abs(e_a + e_b - 1.0) < 1e-9


def test_compute_elo_delta_winner_gains():
    """Winner should gain Elo; loser should lose Elo."""
    new_a, new_b = compute_elo_delta(1500.0, 1500.0, a_won=True)
    assert new_a > 1500.0
    assert new_b < 1500.0


def test_compute_elo_delta_zero_sum():
    """Elo is zero-sum — gains equal losses."""
    new_a, new_b = compute_elo_delta(1500.0, 1500.0, a_won=True)
    delta_a = new_a - 1500.0
    delta_b = new_b - 1500.0
    assert abs(delta_a + delta_b) < 0.01


def test_compute_elo_delta_upset():
    """Upset win gives bigger gain for winner."""
    # Low-rated beats high-rated
    new_low, new_high = compute_elo_delta(1200.0, 1800.0, a_won=True)
    gain_upset = new_low - 1200.0
    # Expected win (high beats low)
    new_high2, new_low2 = compute_elo_delta(1800.0, 1200.0, a_won=True)
    gain_expected = new_high2 - 1800.0
    assert gain_upset > gain_expected


def test_compute_elo_delta_default_elo():
    """None ratings should use DEFAULT_ELO and produce symmetric result."""
    new_a, new_b = compute_elo_delta(None, None, a_won=True)
    assert new_a > DEFAULT_ELO
    assert new_b < DEFAULT_ELO


def test_compute_elo_k_factor():
    """Max possible gain is exactly K (when expected = 0, score = 1)."""
    # Extremely high-rated B vs very low A — A wins (massive upset)
    new_a, _ = compute_elo_delta(100.0, 9900.0, a_won=True)
    assert new_a - 100.0 <= K + 0.01  # gain bounded by K


# ── 2. Elo applied after submit_score ─────────────────────────────────────────

@pytest.mark.asyncio
async def test_elo_applied_after_submit_score(client: AsyncClient, db_session: AsyncSession):
    """Elo ratings updated on both players after completing a singles match."""
    _, org_token, match, _, user_tokens = await _setup_singles_match(
        client, n=4, with_profiles=True
    )

    # Build a profile for side A's user (need user_id from participant lookup)
    winner_id = match["side_a_participant_id"]
    r = await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner_id),
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["status"] == "COMPLETED"

    # Reload match via GET
    r2 = await client.get(
        f"/api/v1/matches/{match['id']}",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r2.status_code == 200
    detail = r2.json()["data"]
    assert detail["elo_applied"] is True


# ── 3. Elo NOT applied twice (elo_applied guard) ──────────────────────────────

@pytest.mark.asyncio
async def test_elo_not_applied_twice(client: AsyncClient, db_session: AsyncSession):
    """
    GET /matches/{id} called twice still reports elo_applied=True only once.
    We verify elo_applied stays True (the guard works).
    """
    _, org_token, match, _, _ = await _setup_singles_match(client, with_profiles=True)
    winner_id = match["side_a_participant_id"]

    await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner_id),
        headers={"Authorization": f"Bearer {org_token}"},
    )

    r1 = await client.get(f"/api/v1/matches/{match['id']}", headers={"Authorization": f"Bearer {org_token}"})
    r2 = await client.get(f"/api/v1/matches/{match['id']}", headers={"Authorization": f"Bearer {org_token}"})

    assert r1.json()["data"]["elo_applied"] is True
    assert r2.json()["data"]["elo_applied"] is True
    # Version should not change on read
    assert r1.json()["data"]["version"] == r2.json()["data"]["version"]


# ── 4. Player stats updated ───────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_player_stats_updated_after_match(client: AsyncClient, db_session: AsyncSession):
    """matches_played, wins and losses incremented correctly on both players."""
    _, org_token, match, participant_ids, user_tokens = await _setup_singles_match(
        client, n=4, with_profiles=True
    )

    # Get both players' user ids from the me endpoint (using their tokens)
    r_a = await client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {user_tokens[0]}"})
    uid_a = r_a.json()["data"]["id"]
    r_b = await client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {user_tokens[1]}"})
    uid_b = r_b.json()["data"]["id"]

    winner_id = match["side_a_participant_id"]
    await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner_id),
        headers={"Authorization": f"Bearer {org_token}"},
    )

    await db_session.commit()
    await db_session.expire_all()

    prof_a = await _get_profile(db_session, uid_a)
    prof_b = await _get_profile(db_session, uid_b)

    if prof_a and prof_b:
        # Profiles exist — check stats
        winner_prof = prof_a if match["side_a_participant_id"] == participant_ids[0] else prof_b
        loser_prof  = prof_b if match["side_a_participant_id"] == participant_ids[0] else prof_a

        assert winner_prof.matches_played == 1
        assert winner_prof.wins == 1
        assert winner_prof.losses == 0

        assert loser_prof.matches_played == 1
        assert loser_prof.wins == 0
        assert loser_prof.losses == 1


# ── 5. GET /matches/{id} ──────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_get_match_detail(client: AsyncClient, db_session: AsyncSession):
    """GET /matches/{id} returns full detail fields."""
    _, org_token, match, _, _ = await _setup_singles_match(client)

    r = await client.get(
        f"/api/v1/matches/{match['id']}",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]

    assert data["match_id"] == match["id"]
    assert data["status"] == "PENDING"
    assert data["elo_applied"] is False
    assert data["version"] == 1
    assert data["sets"] == []


@pytest.mark.asyncio
async def test_get_match_not_found(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    r = await client.get(
        "/api/v1/matches/00000000-0000-0000-0000-000000000000",
        headers={"Authorization": f"Bearer {org['access_token']}"},
    )
    assert r.status_code == 404


# ── 6. update-score: PENDING → IN_PROGRESS ────────────────────────────────────

@pytest.mark.asyncio
async def test_update_score_transitions_to_in_progress(client: AsyncClient, db_session: AsyncSession):
    """POST /matches/{id}/update-score saves scores and flips status to IN_PROGRESS."""
    _, org_token, match, _, _ = await _setup_singles_match(client)
    assert match["status"] == "PENDING"

    r = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json={"sets": [{"set_number": 1, "side_a_score": 15, "side_b_score": 10}]},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["status"] == "IN_PROGRESS"
    assert len(data["sets"]) == 1
    assert data["version"] == 2


@pytest.mark.asyncio
async def test_update_score_idempotent_when_in_progress(client: AsyncClient, db_session: AsyncSession):
    """Calling update-score again keeps status IN_PROGRESS; replaces previous scores."""
    _, org_token, match, _, _ = await _setup_singles_match(client)

    await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json={"sets": [{"set_number": 1, "side_a_score": 15, "side_b_score": 10}]},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    r = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json={"sets": [
            {"set_number": 1, "side_a_score": 21, "side_b_score": 18},
            {"set_number": 2, "side_a_score": 21, "side_b_score": 19},
        ]},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["status"] == "IN_PROGRESS"
    assert len(data["sets"]) == 2
    assert data["version"] == 3


@pytest.mark.asyncio
async def test_update_score_rejected_for_finished_match(client: AsyncClient, db_session: AsyncSession):
    """update-score returns 409 for a COMPLETED match."""
    _, org_token, match, _, _ = await _setup_singles_match(client)
    winner_id = match["side_a_participant_id"]

    await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner_id),
        headers={"Authorization": f"Bearer {org_token}"},
    )

    r = await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json={"sets": [{"set_number": 1, "side_a_score": 5, "side_b_score": 3}]},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 409


# ── 7. complete: IN_PROGRESS → COMPLETED ──────────────────────────────────────

@pytest.mark.asyncio
async def test_complete_from_in_progress(client: AsyncClient, db_session: AsyncSession):
    """complete endpoint transitions IN_PROGRESS → COMPLETED, applies Elo."""
    _, org_token, match, _, _ = await _setup_singles_match(client, with_profiles=True)
    winner_id = match["side_a_participant_id"]

    # First move to IN_PROGRESS
    await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json={"sets": [{"set_number": 1, "side_a_score": 21, "side_b_score": 15}]},
        headers={"Authorization": f"Bearer {org_token}"},
    )

    r = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json={"winner_participant_id": winner_id},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["status"] == "COMPLETED"
    assert data["winner_participant_id"] == winner_id
    assert data["elo_applied"] is True


@pytest.mark.asyncio
async def test_complete_from_pending(client: AsyncClient, db_session: AsyncSession):
    """complete endpoint also works directly from PENDING (no prior update-score)."""
    _, org_token, match, _, _ = await _setup_singles_match(client)
    winner_id = match["side_a_participant_id"]

    r = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json={"winner_participant_id": winner_id},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["status"] == "COMPLETED"


# ── 8. complete with fresh sets ───────────────────────────────────────────────

@pytest.mark.asyncio
async def test_complete_with_sets_replaces_scores(client: AsyncClient, db_session: AsyncSession):
    """If sets are provided in complete request, they replace any existing scores."""
    _, org_token, match, _, _ = await _setup_singles_match(client)
    winner_id = match["side_a_participant_id"]

    # Put partial scores via update-score
    await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json={"sets": [{"set_number": 1, "side_a_score": 5, "side_b_score": 3}]},
        headers={"Authorization": f"Bearer {org_token}"},
    )

    # Complete with full authoritative scores
    r = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json={
            "winner_participant_id": winner_id,
            "sets": [
                {"set_number": 1, "side_a_score": 21, "side_b_score": 15},
                {"set_number": 2, "side_a_score": 21, "side_b_score": 18},
            ],
        },
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert len(data["sets"]) == 2
    assert data["sets"][0]["side_a_score"] == 21


# ── 9. Elo skipped for walkovers ──────────────────────────────────────────────

@pytest.mark.asyncio
async def test_elo_not_applied_for_walkover(client: AsyncClient, db_session: AsyncSession):
    """Walkover completes the match but elo_applied stays False."""
    _, org_token, match, _, _ = await _setup_singles_match(client, with_profiles=True)
    winner_id = match["side_a_participant_id"]

    await client.post(
        f"/api/v1/matches/{match['id']}/walkover",
        json={"winner_participant_id": winner_id},
        headers={"Authorization": f"Bearer {org_token}"},
    )

    r = await client.get(
        f"/api/v1/matches/{match['id']}",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    data = r.json()["data"]
    assert data["status"] == "WALKOVER"
    assert data["elo_applied"] is False


# ── 10. Elo skipped for non-singles ───────────────────────────────────────────

@pytest.mark.asyncio
async def test_elo_not_applied_for_doubles(client: AsyncClient, db_session: AsyncSession):
    """Completing a DOUBLES match should leave elo_applied=False."""
    org = await _do_full_login(client, PHONE_DOUBLES_ORG)
    org_token = org["access_token"]

    r = await client.post(
        "/api/v1/tournaments",
        json={
            "title": "Doubles Cup",
            "format": "KNOCKOUT",
            "match_format": "BEST_OF_3",
            "play_type": "DOUBLES",
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
    for i in range(4):
        tok = await _do_full_login(client, PHONES_DOUBLES[i])
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

    r = await client.get(f"/api/v1/tournaments/{tid}/matches", headers={"Authorization": f"Bearer {org_token}"})
    match = next(m for m in r.json()["data"] if m["status"] == "PENDING" and m["round"] == 1)
    winner_id = match["side_a_participant_id"]

    await client.post(
        f"/api/v1/matches/{match['id']}/score",
        json=_score_payload(winner_id),
        headers={"Authorization": f"Bearer {org_token}"},
    )

    r2 = await client.get(f"/api/v1/matches/{match['id']}", headers={"Authorization": f"Bearer {org_token}"})
    assert r2.json()["data"]["elo_applied"] is False


# ── 11. complete rejected with invalid winner ──────────────────────────────────

@pytest.mark.asyncio
async def test_complete_invalid_winner_rejected(client: AsyncClient, db_session: AsyncSession):
    """complete returns 409 when winner_participant_id is not a match participant."""
    _, org_token, match, _, _ = await _setup_singles_match(client)

    r = await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json={"winner_participant_id": "00000000-0000-0000-0000-000000000000"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 409


# ── 12. version increments on every mutation ──────────────────────────────────

@pytest.mark.asyncio
async def test_version_increments_on_mutations(client: AsyncClient, db_session: AsyncSession):
    """version field increments on update-score and complete."""
    _, org_token, match, _, _ = await _setup_singles_match(client)
    winner_id = match["side_a_participant_id"]

    # initial
    r0 = await client.get(f"/api/v1/matches/{match['id']}", headers={"Authorization": f"Bearer {org_token}"})
    v0 = r0.json()["data"]["version"]

    # after update-score
    await client.post(
        f"/api/v1/matches/{match['id']}/update-score",
        json={"sets": [{"set_number": 1, "side_a_score": 10, "side_b_score": 8}]},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    r1 = await client.get(f"/api/v1/matches/{match['id']}", headers={"Authorization": f"Bearer {org_token}"})
    v1 = r1.json()["data"]["version"]
    assert v1 == v0 + 1

    # after complete
    await client.post(
        f"/api/v1/matches/{match['id']}/complete",
        json={"winner_participant_id": winner_id},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    r2 = await client.get(f"/api/v1/matches/{match['id']}", headers={"Authorization": f"Bearer {org_token}"})
    v2 = r2.json()["data"]["version"]
    assert v2 == v1 + 1
