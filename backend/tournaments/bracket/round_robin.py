"""
Round-robin schedule generation using the circle method.

Pure function — no DB access.
"""

import uuid
from typing import Optional

from common.enums import MatchStatus
from tournaments.models import Match


def generate_round_robin_bracket(
    tournament_id: uuid.UUID,
    participant_ids: list[uuid.UUID],
) -> list[Match]:
    players: list[Optional[uuid.UUID]] = list(participant_ids)
    if len(players) % 2 == 1:
        players.append(None)  # virtual bye

    n = len(players)
    fixed = players[0]
    rotating = list(players[1:])

    matches: list[Match] = []

    for round_num in range(1, n):
        # Build pairs for this round
        current = [fixed] + rotating
        match_num = 0
        for i in range(n // 2):
            a = current[i]
            b = current[n - 1 - i]
            if a is not None and b is not None:
                match_num += 1
                matches.append(
                    Match(
                        id=uuid.uuid4(),
                        tournament_id=tournament_id,
                        round=round_num,
                        match_number=match_num,
                        side_a_participant_id=a,
                        side_b_participant_id=b,
                        status=MatchStatus.PENDING.value,
                    )
                )
        # Rotate: last element moves to front of rotating list
        rotating = [rotating[-1]] + rotating[:-1]

    return matches
