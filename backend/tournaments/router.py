import uuid
from typing import Annotated, Optional

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

import tournaments.service as svc
from common.dependencies import get_current_user
from common.pagination import PageParams, paginate
from common.response import ok
from database import get_db
from tournaments.schemas import (
    MatchResponse,
    ParticipantRegisterRequest,
    ParticipantResponse,
    SeedOrderRequest,
    StandingEntry,
    TournamentCreate,
    TournamentResponse,
    TournamentStatusTransitionRequest,
    TournamentUpdate,
)
from users.models import User

router = APIRouter(prefix="/tournaments", tags=["tournaments"])


# ── Tournament CRUD ───────────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED)
async def create_tournament(
    body: TournamentCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    t = await svc.create_tournament(db, current_user.id, body)
    return ok(TournamentResponse.model_validate(t).model_dump())


@router.get("", status_code=status.HTTP_200_OK)
async def list_tournaments(
    params: Annotated[PageParams, Depends()],
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    city: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    format: Optional[str] = Query(None),
) -> dict:
    items, total = await svc.list_tournaments(db, params, city=city, status=status, format=format)
    return paginate([TournamentResponse.model_validate(t).model_dump() for t in items], total, params)


@router.get("/{tournament_id}", status_code=status.HTTP_200_OK)
async def get_tournament(
    tournament_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> dict:
    t = await svc.get_tournament(db, tournament_id)
    return ok(TournamentResponse.model_validate(t).model_dump())


@router.put("/{tournament_id}", status_code=status.HTTP_200_OK)
async def update_tournament(
    tournament_id: uuid.UUID,
    body: TournamentUpdate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    t = await svc.update_tournament(db, tournament_id, current_user.id, body)
    return ok(TournamentResponse.model_validate(t).model_dump())


@router.delete("/{tournament_id}", status_code=status.HTTP_200_OK)
async def cancel_tournament(
    tournament_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    await svc.cancel_tournament(db, tournament_id, current_user.id)
    return ok({"message": "Tournament cancelled"})


@router.post("/{tournament_id}/status", status_code=status.HTTP_200_OK)
async def transition_status(
    tournament_id: uuid.UUID,
    body: TournamentStatusTransitionRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    t = await svc.transition_status(db, tournament_id, current_user.id, body.next_status)
    return ok(TournamentResponse.model_validate(t).model_dump())


# ── Participants ──────────────────────────────────────────────

@router.post("/{tournament_id}/participants", status_code=status.HTTP_201_CREATED)
async def register_participant(
    tournament_id: uuid.UUID,
    body: ParticipantRegisterRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    p = await svc.register_participant(db, tournament_id, current_user.id, body)
    return ok(ParticipantResponse.model_validate(p).model_dump())


@router.get("/{tournament_id}/participants", status_code=status.HTTP_200_OK)
async def list_participants(
    tournament_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    params: Annotated[PageParams, Depends()],
) -> dict:
    items = await svc.list_participants(db, tournament_id)
    return paginate(
        [ParticipantResponse.model_validate(p).model_dump() for p in items],
        len(items), params,
    )


@router.delete("/{tournament_id}/participants/{participant_id}", status_code=status.HTTP_200_OK)
async def withdraw_participant(
    tournament_id: uuid.UUID,
    participant_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    await svc.withdraw_participant(db, tournament_id, participant_id, current_user.id)
    return ok({"message": "Withdrawn successfully"})


@router.put("/{tournament_id}/participants/seed-order", status_code=status.HTTP_200_OK)
async def set_seed_order(
    tournament_id: uuid.UUID,
    body: SeedOrderRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    await svc.set_seed_order(db, tournament_id, current_user.id, body.ordered_participant_ids)
    items = await svc.list_participants(db, tournament_id)
    return ok([ParticipantResponse.model_validate(p).model_dump() for p in items])


# ── Bracket ───────────────────────────────────────────────────

@router.post("/{tournament_id}/bracket/generate", status_code=status.HTTP_201_CREATED)
async def generate_bracket(
    tournament_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    matches = await svc.generate_bracket(db, tournament_id, current_user.id)
    return ok({"matches_created": len(matches)})


@router.get("/{tournament_id}/bracket", status_code=status.HTTP_200_OK)
async def get_bracket(
    tournament_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    matches = await svc.get_matches(db, tournament_id)
    return ok([MatchResponse.model_validate(m).model_dump() for m in matches])


@router.get("/{tournament_id}/matches", status_code=status.HTTP_200_OK)
async def list_matches(
    tournament_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    matches = await svc.get_matches(db, tournament_id)
    return ok([MatchResponse.model_validate(m).model_dump() for m in matches])


@router.get("/{tournament_id}/standings", status_code=status.HTTP_200_OK)
async def get_standings(
    tournament_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    standings = await svc.get_round_robin_standings(db, tournament_id)
    return ok(standings)
