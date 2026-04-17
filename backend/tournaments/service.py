"""
Tournament service — covers P3 (CRUD), P4 (participants), P5/P7 (brackets), P6 (score integration).
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from common.enums import (
    TOURNAMENT_STATUS_TRANSITIONS,
    MatchFormat,
    MatchStatus,
    ParticipantStatus,
    TournamentFormat,
    TournamentStatus,
)
from common.exceptions import ConflictError, ForbiddenError, NotFoundError, ValidationError
from common.pagination import PageParams
from tournaments.models import Match, MatchScore, Tournament, TournamentParticipant
from tournaments.schemas import (
    ParticipantRegisterRequest,
    TournamentCreate,
    TournamentUpdate,
)
from users.models import User


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Tournament CRUD (P3) ──────────────────────────────────────


async def create_tournament(
    db: AsyncSession, organiser_id: uuid.UUID, data: TournamentCreate
) -> Tournament:
    t = Tournament(
        organiser_id=organiser_id,
        title=data.title,
        description=data.description,
        city=data.city,
        format=data.format.value,
        match_format=data.match_format.value,
        play_type=data.play_type.value,
        status=TournamentStatus.DRAFT.value,
        max_participants=data.max_participants,
        registration_deadline=data.registration_deadline,
        starts_at=data.starts_at,
    )
    db.add(t)
    await db.flush()
    return t


async def get_tournament(db: AsyncSession, tournament_id: uuid.UUID) -> Tournament:
    result = await db.execute(
        select(Tournament).where(Tournament.id == tournament_id, Tournament.deleted_at.is_(None))
    )
    t = result.scalar_one_or_none()
    if t is None:
        raise NotFoundError("Tournament not found")
    return t


async def list_tournaments(
    db: AsyncSession,
    params: PageParams,
    city: str | None = None,
    status: str | None = None,
    format: str | None = None,
) -> tuple[list[Tournament], int]:
    q = select(Tournament).where(Tournament.deleted_at.is_(None))
    if city:
        q = q.where(func.lower(Tournament.city) == city.lower())
    if status:
        q = q.where(Tournament.status == status)
    if format:
        q = q.where(Tournament.format == format)

    total_result = await db.execute(select(func.count()).select_from(q.subquery()))
    total = total_result.scalar_one()

    q = q.order_by(Tournament.created_at.desc()).offset(params.offset).limit(params.limit)
    result = await db.execute(q)
    return list(result.scalars().all()), total


async def update_tournament(
    db: AsyncSession, tournament_id: uuid.UUID, organiser_id: uuid.UUID, data: TournamentUpdate
) -> Tournament:
    t = await get_tournament(db, tournament_id)
    if t.organiser_id != organiser_id:
        raise ForbiddenError("Only the organiser can update this tournament")
    if t.status not in (TournamentStatus.DRAFT.value, TournamentStatus.REGISTRATION_OPEN.value):
        raise ConflictError("Tournament can only be updated in DRAFT or REGISTRATION_OPEN status")

    if data.title is not None:
        t.title = data.title
    if data.description is not None:
        t.description = data.description
    if data.city is not None:
        t.city = data.city
    if data.match_format is not None:
        t.match_format = data.match_format.value
    if data.play_type is not None:
        t.play_type = data.play_type.value
    if data.max_participants is not None:
        t.max_participants = data.max_participants
    if data.registration_deadline is not None:
        t.registration_deadline = data.registration_deadline
    if data.starts_at is not None:
        t.starts_at = data.starts_at

    await db.flush()
    return t


async def transition_status(
    db: AsyncSession,
    tournament_id: uuid.UUID,
    organiser_id: uuid.UUID,
    next_status: TournamentStatus,
) -> Tournament:
    t = await get_tournament(db, tournament_id)
    if t.organiser_id != organiser_id:
        raise ForbiddenError("Only the organiser can change tournament status")

    current = TournamentStatus(t.status)
    allowed = TOURNAMENT_STATUS_TRANSITIONS[current]
    if next_status not in allowed:
        raise ConflictError(f"Cannot transition from {current.value} to {next_status.value}")

    # Re-opening requires bracket not yet generated
    if next_status == TournamentStatus.REGISTRATION_OPEN and t.bracket_generated:
        raise ConflictError("Cannot reopen registration after bracket has been generated")

    t.status = next_status.value
    await db.flush()
    return t


async def cancel_tournament(
    db: AsyncSession, tournament_id: uuid.UUID, organiser_id: uuid.UUID
) -> Tournament:
    t = await get_tournament(db, tournament_id)
    if t.organiser_id != organiser_id:
        raise ForbiddenError("Only the organiser can cancel this tournament")
    t.status = TournamentStatus.CANCELLED.value
    t.deleted_at = _now()
    await db.flush()
    return t


# ── Participants (P4) ─────────────────────────────────────────


async def register_participant(
    db: AsyncSession,
    tournament_id: uuid.UUID,
    user_id: uuid.UUID,
    data: ParticipantRegisterRequest,
) -> TournamentParticipant:
    t = await get_tournament(db, tournament_id)

    if t.organiser_id == user_id:
        raise ForbiddenError("Organisers cannot register in their own tournament")
    if t.status != TournamentStatus.REGISTRATION_OPEN.value:
        raise ConflictError("Tournament is not open for registration")
    if t.registration_deadline and _now() > t.registration_deadline:
        raise ConflictError("Registration deadline has passed")

    # Duplicate check
    dup = await db.execute(
        select(TournamentParticipant).where(
            TournamentParticipant.tournament_id == tournament_id,
            TournamentParticipant.user_id == user_id,
            TournamentParticipant.status == ParticipantStatus.REGISTERED.value,
        )
    )
    if dup.scalar_one_or_none():
        raise ConflictError("Already registered for this tournament")

    # Capacity check
    if t.max_participants:
        count_result = await db.execute(
            select(func.count(TournamentParticipant.id)).where(
                TournamentParticipant.tournament_id == tournament_id,
                TournamentParticipant.status == ParticipantStatus.REGISTERED.value,
            )
        )
        if count_result.scalar_one() >= t.max_participants:
            raise ConflictError("Tournament is full")

    # Partner check (doubles)
    partner_user_id = data.partner_user_id
    if partner_user_id:
        partner_result = await db.execute(select(User).where(User.id == partner_user_id))
        if not partner_result.scalar_one_or_none():
            raise NotFoundError("Partner user not found")
        partner_dup = await db.execute(
            select(TournamentParticipant).where(
                TournamentParticipant.tournament_id == tournament_id,
                TournamentParticipant.user_id == partner_user_id,
                TournamentParticipant.status == ParticipantStatus.REGISTERED.value,
            )
        )
        if partner_dup.scalar_one_or_none():
            raise ConflictError("Partner is already registered in this tournament")

    p = TournamentParticipant(
        tournament_id=tournament_id,
        user_id=user_id,
        partner_user_id=partner_user_id,
        status=ParticipantStatus.REGISTERED.value,
    )
    db.add(p)
    await db.flush()
    return p


async def list_participants(
    db: AsyncSession, tournament_id: uuid.UUID
) -> list[TournamentParticipant]:
    result = await db.execute(
        select(TournamentParticipant)
        .where(TournamentParticipant.tournament_id == tournament_id)
        .order_by(
            TournamentParticipant.seed_order.nulls_last(),
            TournamentParticipant.registered_at,
        )
    )
    return list(result.scalars().all())


async def withdraw_participant(
    db: AsyncSession, tournament_id: uuid.UUID, participant_id: uuid.UUID, user_id: uuid.UUID
) -> TournamentParticipant:
    t = await get_tournament(db, tournament_id)
    if t.status in (TournamentStatus.IN_PROGRESS.value, TournamentStatus.COMPLETED.value):
        raise ConflictError("Cannot withdraw after tournament has started")

    result = await db.execute(
        select(TournamentParticipant).where(
            TournamentParticipant.id == participant_id,
            TournamentParticipant.tournament_id == tournament_id,
        )
    )
    p = result.scalar_one_or_none()
    if p is None:
        raise NotFoundError("Participant not found")
    if p.user_id != user_id:
        raise ForbiddenError("Can only withdraw your own registration")

    p.status = ParticipantStatus.WITHDRAWN.value
    await db.flush()
    return p


async def set_seed_order(
    db: AsyncSession,
    tournament_id: uuid.UUID,
    organiser_id: uuid.UUID,
    ordered_ids: list[uuid.UUID],
) -> list[TournamentParticipant]:
    t = await get_tournament(db, tournament_id)
    if t.organiser_id != organiser_id:
        raise ForbiddenError("Only the organiser can set seed order")

    result = await db.execute(
        select(TournamentParticipant).where(
            TournamentParticipant.tournament_id == tournament_id,
            TournamentParticipant.status == ParticipantStatus.REGISTERED.value,
        )
    )
    participants = {p.id: p for p in result.scalars().all()}

    for pid in ordered_ids:
        if pid not in participants:
            raise ValidationError(f"Participant {pid} not found in this tournament")

    for idx, pid in enumerate(ordered_ids, start=1):
        participants[pid].seed_order = idx

    await db.flush()
    return list(participants.values())


# ── Bracket generation (P5 / P7) ─────────────────────────────


async def generate_bracket(
    db: AsyncSession, tournament_id: uuid.UUID, organiser_id: uuid.UUID
) -> list[Match]:
    from tournaments.bracket.knockout import generate_knockout_bracket
    from tournaments.bracket.round_robin import generate_round_robin_bracket

    t = await get_tournament(db, tournament_id)
    if t.organiser_id != organiser_id:
        raise ForbiddenError("Only the organiser can generate the bracket")
    if t.bracket_generated:
        raise ConflictError("Bracket has already been generated")
    if t.status != TournamentStatus.REGISTRATION_CLOSED.value:
        raise ConflictError("Tournament must be in REGISTRATION_CLOSED status to generate bracket")

    participants = await list_participants(db, tournament_id)
    registered = [p for p in participants if p.status == ParticipantStatus.REGISTERED.value]
    if len(registered) < 4:
        raise ConflictError("At least 4 registered participants are required")

    participant_ids = [p.id for p in registered]

    if t.format == TournamentFormat.KNOCKOUT.value:
        matches = generate_knockout_bracket(tournament_id, participant_ids)
    else:
        matches = generate_round_robin_bracket(tournament_id, participant_ids)

    for m in matches:
        db.add(m)
    await db.flush()

    t.bracket_generated = True
    t.status = TournamentStatus.IN_PROGRESS.value
    await db.flush()

    return matches


async def get_matches(db: AsyncSession, tournament_id: uuid.UUID) -> list[Match]:
    result = await db.execute(
        select(Match)
        .where(Match.tournament_id == tournament_id)
        .order_by(Match.round, Match.match_number)
    )
    return list(result.scalars().all())


async def get_match(db: AsyncSession, match_id: uuid.UUID) -> Match:
    result = await db.execute(select(Match).where(Match.id == match_id))
    m = result.scalar_one_or_none()
    if m is None:
        raise NotFoundError("Match not found")
    return m


async def get_round_robin_standings(
    db: AsyncSession, tournament_id: uuid.UUID
) -> list[dict]:
    t = await get_tournament(db, tournament_id)
    if t.format != TournamentFormat.ROUND_ROBIN.value:
        raise ConflictError("Standings are only available for round robin tournaments")

    matches = await get_matches(db, tournament_id)
    participants = await list_participants(db, tournament_id)

    stats: dict[uuid.UUID, dict] = {
        p.id: {"participant_id": p.id, "user_id": p.user_id,
               "matches_played": 0, "wins": 0, "losses": 0, "points": 0}
        for p in participants if p.status == ParticipantStatus.REGISTERED.value
    }

    for m in matches:
        if m.status != MatchStatus.COMPLETED.value and m.status != MatchStatus.WALKOVER.value:
            continue
        if m.side_a_participant_id and m.side_a_participant_id in stats:
            stats[m.side_a_participant_id]["matches_played"] += 1
        if m.side_b_participant_id and m.side_b_participant_id in stats:
            stats[m.side_b_participant_id]["matches_played"] += 1

        if m.winner_participant_id and m.winner_participant_id in stats:
            stats[m.winner_participant_id]["wins"] += 1
            stats[m.winner_participant_id]["points"] += 2
            # loser
            loser_id = (
                m.side_b_participant_id
                if m.winner_participant_id == m.side_a_participant_id
                else m.side_a_participant_id
            )
            if loser_id and loser_id in stats:
                stats[loser_id]["losses"] += 1

    return sorted(stats.values(), key=lambda x: x["points"], reverse=True)
