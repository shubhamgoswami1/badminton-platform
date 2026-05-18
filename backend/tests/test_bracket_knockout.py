"""
P5 Knockout bracket tests — 11 required cases.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.test_auth import _do_full_login

PHONE_ORG = "+913000000001"
PHONES = [f"+91300000{i:04d}" for i in range(2, 20)]

# Distinct phones for the rating-seeding test — no collision with the pool above.
PHONE_SEED_ORG = "+916000000001"
PHONE_SEED_P1  = "+916000000002"   # rating 10 (top seed)
PHONE_SEED_P2  = "+916000000003"   # rating  8
PHONE_SEED_P3  = "+916000000004"   # rating  6
PHONE_SEED_P4  = "+916000000005"   # rating  4 (bottom seed)


# ── Helpers ───────────────────────────────────────────────────


async def _setup_tournament_with_participants(
    client: AsyncClient, n: int, fmt: str = "KNOCKOUT"
) -> tuple[str, str, list[str]]:
    """Create tournament, register n participants, close registration. Returns (tid, org_token, participant_ids)."""
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]

    r = await client.post(
        "/api/v1/tournaments",
        json={"title": "KO Cup", "format": fmt, "match_format": "BEST_OF_3", "play_type": "SINGLES"},
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

    return tid, org_token, participant_ids


# ── Test cases ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_generate_bracket_4_players(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, _ = await _setup_tournament_with_participants(client, 4)

    r = await client.post(
        f"/api/v1/tournaments/{tid}/bracket/generate",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 201
    # 4 players → bracket_size=4 → 3 matches (2 R1 + 1 final)
    assert r.json()["data"]["matches_created"] == 3


@pytest.mark.asyncio
async def test_generate_bracket_8_players(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, _ = await _setup_tournament_with_participants(client, 8)

    r = await client.post(
        f"/api/v1/tournaments/{tid}/bracket/generate",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 201
    assert r.json()["data"]["matches_created"] == 7


@pytest.mark.asyncio
async def test_generate_bracket_5_players_has_byes(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, _ = await _setup_tournament_with_participants(client, 5)

    r = await client.post(
        f"/api/v1/tournaments/{tid}/bracket/generate",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 201
    # 5 players → bracket_size=8 → 7 match slots (some BYE)
    assert r.json()["data"]["matches_created"] == 7


@pytest.mark.asyncio
async def test_generate_bracket_sets_tournament_in_progress(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, _ = await _setup_tournament_with_participants(client, 4)

    await client.post(
        f"/api/v1/tournaments/{tid}/bracket/generate",
        headers={"Authorization": f"Bearer {org_token}"},
    )

    r = await client.get(
        f"/api/v1/tournaments/{tid}",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    data = r.json()["data"]
    assert data["status"] == "IN_PROGRESS"
    assert data["bracket_generated"] is True


@pytest.mark.asyncio
async def test_generate_bracket_idempotent_rejected(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, _ = await _setup_tournament_with_participants(client, 4)

    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})
    r = await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 409


@pytest.mark.asyncio
async def test_generate_bracket_forbidden(client: AsyncClient, db_session: AsyncSession):
    tid, _, _ = await _setup_tournament_with_participants(client, 4)
    other = await _do_full_login(client, "+913000000099")

    r = await client.post(
        f"/api/v1/tournaments/{tid}/bracket/generate",
        headers={"Authorization": f"Bearer {other['access_token']}"},
    )
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_generate_bracket_too_few_participants(client: AsyncClient, db_session: AsyncSession):
    org = await _do_full_login(client, PHONE_ORG)
    org_token = org["access_token"]

    r = await client.post(
        "/api/v1/tournaments",
        json={"title": "Small Cup", "format": "KNOCKOUT", "match_format": "BEST_OF_3", "play_type": "SINGLES"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    tid = r.json()["data"]["id"]
    await client.post(f"/api/v1/tournaments/{tid}/status", json={"next_status": "REGISTRATION_OPEN"}, headers={"Authorization": f"Bearer {org_token}"})

    # Register only 3 participants
    for i in range(3):
        t = await _do_full_login(client, PHONES[i])
        await client.post(f"/api/v1/tournaments/{tid}/participants", json={}, headers={"Authorization": f"Bearer {t['access_token']}"})

    await client.post(f"/api/v1/tournaments/{tid}/status", json={"next_status": "REGISTRATION_CLOSED"}, headers={"Authorization": f"Bearer {org_token}"})

    r = await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 409


@pytest.mark.asyncio
async def test_get_bracket(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, _ = await _setup_tournament_with_participants(client, 4)
    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})

    r = await client.get(f"/api/v1/tournaments/{tid}/bracket", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 200
    matches = r.json()["data"]
    assert len(matches) == 3


@pytest.mark.asyncio
async def test_bracket_next_match_links(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, _ = await _setup_tournament_with_participants(client, 4)
    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})

    r = await client.get(f"/api/v1/tournaments/{tid}/bracket", headers={"Authorization": f"Bearer {org_token}"})
    matches = r.json()["data"]
    by_round = {}
    for m in matches:
        by_round.setdefault(m["round"], []).append(m)

    # R1 matches should have next_match_id pointing to final
    final_ids = {m["id"] for m in by_round[2]}
    for m in by_round[1]:
        assert m["next_match_id"] in final_ids


@pytest.mark.asyncio
async def test_bye_propagation(client: AsyncClient, db_session: AsyncSession):
    """With 5 players → bracket_size=8 → 3 R1 byes. Bye winners should appear in R2."""
    tid, org_token, _ = await _setup_tournament_with_participants(client, 5)
    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})

    r = await client.get(f"/api/v1/tournaments/{tid}/bracket", headers={"Authorization": f"Bearer {org_token}"})
    matches = r.json()["data"]

    r2_matches = [m for m in matches if m["round"] == 2]
    # At least some R2 slots should already be filled from BYE propagation
    filled = sum(1 for m in r2_matches if m["side_a_participant_id"] or m["side_b_participant_id"])
    assert filled > 0


@pytest.mark.asyncio
async def test_list_matches(client: AsyncClient, db_session: AsyncSession):
    tid, org_token, _ = await _setup_tournament_with_participants(client, 4)
    await client.post(f"/api/v1/tournaments/{tid}/bracket/generate", headers={"Authorization": f"Bearer {org_token}"})

    r = await client.get(f"/api/v1/tournaments/{tid}/matches", headers={"Authorization": f"Bearer {org_token}"})
    assert r.status_code == 200
    assert len(r.json()["data"]) == 3


@pytest.mark.asyncio
async def test_knockout_seeding_by_rating(client: AsyncClient, db_session: AsyncSession):
    """
    Players with distinct ratings should be seeded highest-first so that the
    standard 1-vs-N pairing produces:
      R1 Match A: top seed (rating 10) vs bottom seed (rating 4)
      R1 Match B: 2nd seed (rating  8) vs 3rd seed  (rating 6)
    """
    # --- create organiser ---
    org = await _do_full_login(client, PHONE_SEED_ORG)
    org_token = org["access_token"]

    # --- create tournament ---
    r = await client.post(
        "/api/v1/tournaments",
        json={"title": "Seed Cup", "format": "KNOCKOUT",
              "match_format": "BEST_OF_3", "play_type": "SINGLES"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 201, r.text
    tid = r.json()["data"]["id"]

    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_OPEN"},
        headers={"Authorization": f"Bearer {org_token}"},
    )

    # --- register 4 players with explicit ratings ---
    player_phones  = [PHONE_SEED_P1, PHONE_SEED_P2, PHONE_SEED_P3, PHONE_SEED_P4]
    player_ratings = [10.0, 8.0, 6.0, 4.0]
    participant_ids: list[str] = []

    for phone, rating in zip(player_phones, player_ratings):
        tok = (await _do_full_login(client, phone))["access_token"]

        # Set player profile with a rating
        pr = await client.put(
            "/api/v1/users/me/profile",
            json={"display_name": f"Player-{int(rating)}", "rating": rating},
            headers={"Authorization": f"Bearer {tok}"},
        )
        assert pr.status_code == 200, pr.text

        reg = await client.post(
            f"/api/v1/tournaments/{tid}/participants",
            json={},
            headers={"Authorization": f"Bearer {tok}"},
        )
        assert reg.status_code == 201, reg.text
        participant_ids.append(reg.json()["data"]["id"])

    pid_top, pid_2nd, pid_3rd, pid_bot = participant_ids

    # --- close registration and generate bracket ---
    await client.post(
        f"/api/v1/tournaments/{tid}/status",
        json={"next_status": "REGISTRATION_CLOSED"},
        headers={"Authorization": f"Bearer {org_token}"},
    )
    gen = await client.post(
        f"/api/v1/tournaments/{tid}/bracket/generate",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert gen.status_code == 201, gen.text

    # --- fetch R1 matches ---
    r = await client.get(
        f"/api/v1/tournaments/{tid}/bracket",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert r.status_code == 200, r.text
    matches = r.json()["data"]
    r1_matches = [m for m in matches if m["round"] == 1]
    assert len(r1_matches) == 2

    r1_pairs = [
        frozenset([m["side_a_participant_id"], m["side_b_participant_id"]])
        for m in r1_matches
    ]

    # 1 vs N: top-seed plays bottom-seed; 2nd seed plays 3rd seed
    assert frozenset([pid_top, pid_bot]) in r1_pairs, (
        f"Expected top ({pid_top}) vs bottom ({pid_bot}) in R1; got {r1_pairs}"
    )
    assert frozenset([pid_2nd, pid_3rd]) in r1_pairs, (
        f"Expected 2nd ({pid_2nd}) vs 3rd ({pid_3rd}) in R1; got {r1_pairs}"
    )
