"""
Score submission service — P6.

Handles submitting set scores, recording winner, and advancing the winner
in knockout brackets (populating the next match's side slot).
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from common.enums import MatchStatus, TournamentFormat
from common.exceptions import ConflictError, ForbiddenError, NotFoundError
from scores.schemas import SubmitScoreRequest
from tournaments.models import Match, MatchScore, Tournament, TournamentParticipant


def _now() -> datetime:
    return datetime.now(timezone.utc)


async def _get_match(db: AsyncSession, match_id: uuid.UUID) -> Match:
    result = await db.execute(select(Match).where(Match.id == match_id))
    m = result.scalar_one_or_none()
    if m is None:
        raise NotFoundError("Match not found")
    return m


async def _get_tournament(db: AsyncSession, tournament_id: uuid.UUID) -> Tournament:
    result = await db.execute(select(Tournament).where(Tournament.id == tournament_id))
    t = result.scalar_one_or_none()
    if t is None:
        raise NotFoundError("Tournament not found")
    return t


async def submit_score(
    db: AsyncSession,
    match_id: uuid.UUID,
    user_id: uuid.UUID,
    data: SubmitScoreRequest,
) -> Match:
    match = await _get_match(db, match_id)

    if match.status in (MatchStatus.COMPLETED.value, MatchStatus.WALKOVER.value):
        raise ConflictError("Match score has already been submitted")
    if match.status == MatchStatus.BYE.value:
        raise ConflictError("Cannot submit score for a BYE match")

    t = await _get_tournament(db, match.tournament_id)

    # Only organiser or one of the participants may submit
    organiser_result = await db.execute(
        select(Tournament).where(Tournament.id == match.tournament_id)
    )
    organiser_id = t.organiser_id

    allowed_participants = {match.side_a_participant_id, match.side_b_participant_id}
    # Resolve participant → user
    if user_id != organiser_id:
        part_result = await db.execute(
            select(TournamentParticipant).where(
                TournamentParticipant.id.in_([p for p in allowed_participants if p])
            )
        )
        participant_user_ids = {p.user_id for p in part_result.scalars().all()}
        if user_id not in participant_user_ids:
            raise ForbiddenError("Only the organiser or a participant of this match can submit scores")

    # Validate winner is one of the sides
    winner_id = data.winner_participant_id
    if winner_id not in allowed_participants:
        raise ConflictError("Winner must be one of the match participants")

    # Delete any existing scores for idempotency
    existing = await db.execute(select(MatchScore).where(MatchScore.match_id == match_id))
    for s in existing.scalars().all():
        await db.delete(s)

    for s in data.sets:
        db.add(
            MatchScore(
                match_id=match_id,
                set_number=s.set_number,
                side_a_score=s.side_a_score,
                side_b_score=s.side_b_score,
                submitted_by=user_id,
            )
        )

    match.winner_participant_id = winner_id
    match.status = MatchStatus.COMPLETED.value
    match.completed_at = _now()
    await db.flush()

    # For knockout: propagate winner to next match
    if t.format == TournamentFormat.KNOCKOUT.value and match.next_match_id:
        next_match = await _get_match(db, match.next_match_id)
        if match.winner_feeds_side == "A":
            next_match.side_a_participant_id = winner_id
        else:
            next_match.side_b_participant_id = winner_id
        await db.flush()

    return match


async def get_match_scores(db: AsyncSession, match_id: uuid.UUID) -> tuple[Match, list[MatchScore]]:
    match = await _get_match(db, match_id)
    result = await db.execute(
        select(MatchScore).where(MatchScore.match_id == match_id).order_by(MatchScore.set_number)
    )
    return match, list(result.scalars().all())


async def record_walkover(
    db: AsyncSession,
    match_id: uuid.UUID,
    organiser_id: uuid.UUID,
    winner_participant_id: uuid.UUID,
) -> Match:
    match = await _get_match(db, match_id)
    t = await _get_tournament(db, match.tournament_id)

    if t.organiser_id != organiser_id:
        raise ForbiddenError("Only the organiser can record a walkover")
    if match.status in (MatchStatus.COMPLETED.value, MatchStatus.WALKOVER.value):
        raise ConflictError("Match already has a result")

    allowed_participants = {match.side_a_participant_id, match.side_b_participant_id}
    if winner_participant_id not in allowed_participants:
        raise ConflictError("Winner must be one of the match participants")

    match.winner_participant_id = winner_participant_id
    match.status = MatchStatus.WALKOVER.value
    match.completed_at = _now()
    await db.flush()

    if t.format == TournamentFormat.KNOCKOUT.value and match.next_match_id:
        next_match = await _get_match(db, match.next_match_id)
        if match.winner_feeds_side == "A":
            next_match.side_a_participant_id = winner_participant_id
        else:
            next_match.side_b_participant_id = winner_participant_id
        await db.flush()

    return match
