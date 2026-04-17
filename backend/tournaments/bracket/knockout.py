"""
Single-elimination bracket generation.

Pure function — no DB access. Returns a flat list of Match ORM objects
with UUIDs pre-assigned so next_match_id foreign keys are valid.
"""

import uuid
from typing import Optional

from tournaments.models import Match
from common.enums import MatchStatus


def _next_power_of_two(n: int) -> int:
    p = 1
    while p < n:
        p *= 2
    return p


def generate_knockout_bracket(
    tournament_id: uuid.UUID,
    participant_ids: list[uuid.UUID],
) -> list[Match]:
    n = len(participant_ids)
    bracket_size = _next_power_of_two(n)
    num_rounds = bracket_size.bit_length() - 1  # log2(bracket_size)

    # Slots: real participants fill 0..n-1, None (bye) fills n..bracket_size-1
    slots: list[Optional[uuid.UUID]] = list(participant_ids) + [None] * (bracket_size - n)

    # Pre-generate UUIDs for every match so we can set next_match_id up front
    # match_ids[(round, match_num)] → uuid
    match_ids: dict[tuple[int, int], uuid.UUID] = {}
    for r in range(1, num_rounds + 1):
        for m in range(1, (bracket_size // (2 ** r)) + 1):
            match_ids[(r, m)] = uuid.uuid4()

    matches: list[Match] = []
    bye_winners: dict[tuple[int, int], uuid.UUID] = {}  # (round, match_num) → winner_id

    # Build Round 1 matches
    r1_count = bracket_size // 2
    for i in range(r1_count):
        match_num = i + 1
        slot_a = slots[i]
        slot_b = slots[bracket_size - 1 - i]

        next_round = 2 if num_rounds >= 2 else None
        next_match_num = (match_num + 1) // 2 if next_round else None
        feeds_side = "A" if match_num % 2 == 1 else "B"

        if slot_a is None and slot_b is None:
            # Shouldn't happen with valid input, but guard anyway
            status = MatchStatus.BYE.value
            winner_id = None
        elif slot_a is None:
            status = MatchStatus.BYE.value
            winner_id = slot_b
        elif slot_b is None:
            status = MatchStatus.BYE.value
            winner_id = slot_a
        else:
            status = MatchStatus.PENDING.value
            winner_id = None

        m = Match(
            id=match_ids[(1, match_num)],
            tournament_id=tournament_id,
            round=1,
            match_number=match_num,
            side_a_participant_id=slot_a,
            side_b_participant_id=slot_b,
            winner_participant_id=winner_id,
            status=status,
            next_match_id=match_ids[(next_round, next_match_num)] if next_round else None,
            winner_feeds_side=feeds_side if next_round else None,
        )
        matches.append(m)

        if winner_id is not None:
            bye_winners[(1, match_num)] = winner_id

    # Build subsequent rounds as empty shells
    for r in range(2, num_rounds + 1):
        count = bracket_size // (2 ** r)
        for match_num in range(1, count + 1):
            next_round = r + 1 if r < num_rounds else None
            next_match_num = (match_num + 1) // 2 if next_round else None
            feeds_side = "A" if match_num % 2 == 1 else "B"

            m = Match(
                id=match_ids[(r, match_num)],
                tournament_id=tournament_id,
                round=r,
                match_number=match_num,
                status=MatchStatus.PENDING.value,
                next_match_id=match_ids[(next_round, next_match_num)] if next_round else None,
                winner_feeds_side=feeds_side if next_round else None,
            )
            matches.append(m)

    # Propagate BYE winners into their next match's side slot
    match_by_id = {m.id: m for m in matches}
    for m in matches:
        if m.status == MatchStatus.BYE.value and m.winner_participant_id and m.next_match_id:
            next_m = match_by_id[m.next_match_id]
            if m.winner_feeds_side == "A":
                next_m.side_a_participant_id = m.winner_participant_id
            else:
                next_m.side_b_participant_id = m.winner_participant_id

    return matches
