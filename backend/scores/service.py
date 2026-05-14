"""
Score submission service — P6 (updated with Elo, status transitions, stats).

Status transitions
──────────────────
  PENDING → IN_PROGRESS   via update_score()
  PENDING → COMPLETED     via submit_score() or complete_match()
  IN_PROGRESS → COMPLETED via submit_score() or complete_match()

Elo application
───────────────
  Applied once per completed singles match.
  Guard field `match.elo_applied` prevents double application.
  Elo is only applied for PlayType.SINGLES tournaments.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from common.enums import MatchStatus, PlayType, TournamentFormat, TournamentStatus
from common.exceptions import ConflictError, ForbiddenError, NotFoundError
from scores.elo import compute_elo_delta
from scores.schemas import CompleteMatchRequest, SubmitScoreRequest, UpdateScoreRequest
from tournaments.models import Match, MatchScore, Tournament, TournamentParticipant
from users.models import PlayerProfile


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Private helpers ────────────────────────────────────────────────────────────

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


async def _assert_authorised(
    db: AsyncSession,
    match: Match,
    tournament: Tournament,
    user_id: uuid.UUID,
) -> None:
    """Raise ForbiddenError unless user is the organiser or a match participant."""
    if user_id == tournament.organiser_id:
        return

    part_ids = [p for p in (match.side_a_participant_id, match.side_b_participant_id) if p]
    if not part_ids:
        raise ForbiddenError("Only the organiser can act on this match")

    result = await db.execute(
        select(TournamentParticipant).where(TournamentParticipant.id.in_(part_ids))
    )
    participant_user_ids = {p.user_id for p in result.scalars().all()}
    if user_id not in participant_user_ids:
        raise ForbiddenError("Only the organiser or a participant of this match can submit scores")


async def _replace_scores(
    db: AsyncSession,
    match_id: uuid.UUID,
    sets: list,
    submitted_by: uuid.UUID,
) -> None:
    """Delete existing MatchScore rows and insert fresh ones."""
    existing = await db.execute(select(MatchScore).where(MatchScore.match_id == match_id))
    for s in existing.scalars().all():
        await db.delete(s)

    for s in sets:
        db.add(
            MatchScore(
                match_id=match_id,
                set_number=s.set_number,
                side_a_score=s.side_a_score,
                side_b_score=s.side_b_score,
                submitted_by=submitted_by,
            )
        )


async def _propagate_winner(
    db: AsyncSession,
    match: Match,
    tournament: Tournament,
    winner_id: uuid.UUID,
) -> None:
    """For knockout brackets, push the winner into the next match slot."""
    if tournament.format != TournamentFormat.KNOCKOUT.value:
        return
    if not match.next_match_id:
        return

    next_match = await _get_match(db, match.next_match_id)
    if match.winner_feeds_side == "A":
        next_match.side_a_participant_id = winner_id
    else:
        next_match.side_b_participant_id = winner_id
    await db.flush()


async def _maybe_complete_tournament(
    db: AsyncSession,
    tournament_id: uuid.UUID,
) -> None:
    """
    Automatically transition the tournament to COMPLETED when every
    non-BYE match has been finished (COMPLETED or WALKOVER).

    Called after every match result is recorded.  Safe to call repeatedly —
    idempotent if the tournament is already COMPLETED or not IN_PROGRESS.
    """
    t_result = await db.execute(
        select(Tournament).where(Tournament.id == tournament_id)
    )
    t = t_result.scalar_one_or_none()
    if t is None or t.status != TournamentStatus.IN_PROGRESS.value:
        return

    # Fetch all non-BYE matches for the tournament.
    m_result = await db.execute(
        select(Match).where(
            Match.tournament_id == tournament_id,
            Match.status != MatchStatus.BYE.value,
        )
    )
    matches = m_result.scalars().all()

    if not matches:
        return  # No real matches yet — nothing to auto-complete.

    finished = {MatchStatus.COMPLETED.value, MatchStatus.WALKOVER.value}
    if all(m.status in finished for m in matches):
        t.status = TournamentStatus.COMPLETED.value
        t.updated_at = _now()
        await db.flush()


async def _apply_elo(
    db: AsyncSession,
    match: Match,
    tournament: Tournament,
) -> None:
    """
    Apply Elo rating changes for a completed singles match.

    Guards:
      • match.elo_applied must be False (idempotency)
      • tournament.play_type must be SINGLES
      • Both sides must have a participant assigned
    """
    if match.elo_applied:
        return  # Already applied — safe to call multiple times

    if tournament.play_type != PlayType.SINGLES.value:
        return  # Elo only for singles

    if not match.side_a_participant_id or not match.side_b_participant_id:
        return  # Need both sides

    if not match.winner_participant_id:
        return  # Need a winner

    # Resolve participant → user
    part_result = await db.execute(
        select(TournamentParticipant).where(
            TournamentParticipant.id.in_(
                [match.side_a_participant_id, match.side_b_participant_id]
            )
        )
    )
    parts = {p.id: p for p in part_result.scalars().all()}
    part_a = parts.get(match.side_a_participant_id)
    part_b = parts.get(match.side_b_participant_id)

    if not part_a or not part_b:
        return

    # Load PlayerProfiles (Elo silently skipped if profile absent)
    prof_result = await db.execute(
        select(PlayerProfile).where(
            PlayerProfile.user_id.in_([part_a.user_id, part_b.user_id])
        )
    )
    profiles = {p.user_id: p for p in prof_result.scalars().all()}

    prof_a = profiles.get(part_a.user_id)
    prof_b = profiles.get(part_b.user_id)

    a_won = match.winner_participant_id == match.side_a_participant_id

    new_a, new_b = compute_elo_delta(
        prof_a.elo_rating if prof_a else None,
        prof_b.elo_rating if prof_b else None,
        a_won,
    )

    if prof_a is not None:
        prof_a.elo_rating = new_a
        prof_a.matches_played = prof_a.matches_played + 1
        if a_won:
            prof_a.wins = prof_a.wins + 1
        else:
            prof_a.losses = prof_a.losses + 1

    if prof_b is not None:
        prof_b.elo_rating = new_b
        prof_b.matches_played = prof_b.matches_played + 1
        if a_won:
            prof_b.losses = prof_b.losses + 1
        else:
            prof_b.wins = prof_b.wins + 1

    match.elo_applied = True
    await db.flush()


# ── Public service functions ───────────────────────────────────────────────────

async def update_score(
    db: AsyncSession,
    match_id: uuid.UUID,
    user_id: uuid.UUID,
    data: UpdateScoreRequest,
) -> tuple[Match, list[MatchScore]]:
    """
    Save intermediate set scores without completing the match.
    PENDING → IN_PROGRESS (noop if already IN_PROGRESS).
    """
    match = await _get_match(db, match_id)

    if match.status in (MatchStatus.COMPLETED.value, MatchStatus.WALKOVER.value):
        raise ConflictError("Cannot update scores for a finished match")
    if match.status == MatchStatus.BYE.value:
        raise ConflictError("Cannot update scores for a BYE match")

    t = await _get_tournament(db, match.tournament_id)
    await _assert_authorised(db, match, t, user_id)

    await _replace_scores(db, match_id, data.sets, user_id)

    if match.status == MatchStatus.PENDING.value:
        match.status = MatchStatus.IN_PROGRESS.value

    match.version = match.version + 1
    await db.flush()

    score_rows_result = await db.execute(
        select(MatchScore).where(MatchScore.match_id == match_id).order_by(MatchScore.set_number)
    )
    return match, list(score_rows_result.scalars().all())


async def submit_score(
    db: AsyncSession,
    match_id: uuid.UUID,
    user_id: uuid.UUID,
    data: SubmitScoreRequest,
) -> tuple[Match, list[MatchScore]]:
    """
    Submit scores + winner in one shot → COMPLETED.
    Also applies Elo (singles only) and advances knockout bracket.
    """
    match = await _get_match(db, match_id)

    if match.status in (MatchStatus.COMPLETED.value, MatchStatus.WALKOVER.value):
        raise ConflictError("Match score has already been submitted")
    if match.status == MatchStatus.BYE.value:
        raise ConflictError("Cannot submit score for a BYE match")

    t = await _get_tournament(db, match.tournament_id)
    await _assert_authorised(db, match, t, user_id)

    allowed_participants = {match.side_a_participant_id, match.side_b_participant_id}
    winner_id = data.winner_participant_id
    if winner_id not in allowed_participants:
        raise ConflictError("Winner must be one of the match participants")

    await _replace_scores(db, match_id, data.sets, user_id)

    match.winner_participant_id = winner_id
    match.status = MatchStatus.COMPLETED.value
    match.completed_at = _now()
    match.version = match.version + 1
    await db.flush()

    await _apply_elo(db, match, t)
    await _propagate_winner(db, match, t, winner_id)
    await _maybe_complete_tournament(db, match.tournament_id)

    score_rows_result = await db.execute(
        select(MatchScore).where(MatchScore.match_id == match_id).order_by(MatchScore.set_number)
    )
    return match, list(score_rows_result.scalars().all())


async def complete_match(
    db: AsyncSession,
    match_id: uuid.UUID,
    user_id: uuid.UUID,
    data: CompleteMatchRequest,
) -> tuple[Match, list[MatchScore]]:
    """
    Complete a match, optionally replacing scores.
    Accepts PENDING or IN_PROGRESS → COMPLETED.
    Applies Elo (singles only) and advances knockout bracket.
    """
    match = await _get_match(db, match_id)

    if match.status in (MatchStatus.COMPLETED.value, MatchStatus.WALKOVER.value):
        raise ConflictError("Match already has a result")
    if match.status == MatchStatus.BYE.value:
        raise ConflictError("Cannot complete a BYE match")

    t = await _get_tournament(db, match.tournament_id)
    await _assert_authorised(db, match, t, user_id)

    allowed_participants = {match.side_a_participant_id, match.side_b_participant_id}
    winner_id = data.winner_participant_id
    if winner_id not in allowed_participants:
        raise ConflictError("Winner must be one of the match participants")

    if data.sets:
        await _replace_scores(db, match_id, data.sets, user_id)

    match.winner_participant_id = winner_id
    match.status = MatchStatus.COMPLETED.value
    match.completed_at = _now()
    match.version = match.version + 1
    await db.flush()

    await _apply_elo(db, match, t)
    await _propagate_winner(db, match, t, winner_id)
    await _maybe_complete_tournament(db, match.tournament_id)

    score_rows_result = await db.execute(
        select(MatchScore).where(MatchScore.match_id == match_id).order_by(MatchScore.set_number)
    )
    return match, list(score_rows_result.scalars().all())


async def get_match_detail(
    db: AsyncSession,
    match_id: uuid.UUID,
) -> tuple[Match, list[MatchScore]]:
    """Return match + all its score rows."""
    match = await _get_match(db, match_id)
    result = await db.execute(
        select(MatchScore).where(MatchScore.match_id == match_id).order_by(MatchScore.set_number)
    )
    return match, list(result.scalars().all())


async def get_match_scores(
    db: AsyncSession,
    match_id: uuid.UUID,
) -> tuple[Match, list[MatchScore]]:
    """Alias kept for backward compatibility."""
    return await get_match_detail(db, match_id)


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
    match.version = match.version + 1
    await db.flush()

    await _propagate_winner(db, match, t, winner_participant_id)
    await _maybe_complete_tournament(db, match.tournament_id)

    return match


# ── GET /matches/my ────────────────────────────────────────────────────────────

async def get_my_matches(
    db: AsyncSession,
    user_id: uuid.UUID,
    status_filter: list[str] | None = None,
) -> list[dict]:
    """
    Return all matches where the current user is directly assigned as
    side A or side B participant, across all (non-deleted) tournaments.

    Optionally filter by one or more match statuses via `status_filter`.
    Results are ordered newest-first (by match.created_at DESC).

    Each item includes tournament_title and organiser_id so the client
    can build a MatchWithContext-equivalent without extra round-trips.
    """
    # Step 1 — find every participant row belonging to this user.
    part_result = await db.execute(
        select(TournamentParticipant.id).where(
            TournamentParticipant.user_id == user_id,
        )
    )
    participant_ids = [row[0] for row in part_result.all()]

    if not participant_ids:
        return []

    # Step 2 — fetch matches + tournament context in one query.
    q = (
        select(
            Match,
            Tournament.title.label("tournament_title"),
            Tournament.organiser_id.label("organiser_id"),
        )
        .join(Tournament, Tournament.id == Match.tournament_id)
        .where(
            Tournament.deleted_at.is_(None),
            or_(
                Match.side_a_participant_id.in_(participant_ids),
                Match.side_b_participant_id.in_(participant_ids),
            ),
        )
        .order_by(Match.created_at.desc())
    )

    if status_filter:
        q = q.where(Match.status.in_(status_filter))

    rows = (await db.execute(q)).all()

    return [
        {
            "id": row.Match.id,
            "tournament_id": row.Match.tournament_id,
            "round": row.Match.round,
            "match_number": row.Match.match_number,
            "side_a_participant_id": row.Match.side_a_participant_id,
            "side_b_participant_id": row.Match.side_b_participant_id,
            "winner_participant_id": row.Match.winner_participant_id,
            "status": row.Match.status,
            "next_match_id": row.Match.next_match_id,
            "winner_feeds_side": row.Match.winner_feeds_side,
            "scheduled_at": row.Match.scheduled_at,
            "completed_at": row.Match.completed_at,
            "created_at": row.Match.created_at,
            "elo_applied": row.Match.elo_applied,
            "version": row.Match.version,
            "tournament_title": row.tournament_title,
            "organiser_id": row.organiser_id,
        }
        for row in rows
    ]
