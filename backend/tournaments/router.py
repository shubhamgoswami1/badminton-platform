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
    TournamentNearbyResult,
    TournamentResponse,
    TournamentStatusTransitionRequest,
    TournamentUpdate,
)
from users.models import User

router = APIRouter(prefix="/tournaments", tags=["tournaments"])


# ── Discovery endpoints (must be declared BEFORE /{tournament_id}) ─────────

@router.get("/nearby", status_code=status.HTTP_200_OK)
async def get_nearby_tournaments(
    _current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    params: Annotated[PageParams, Depends()],
    lat: float = Query(..., ge=-90.0, le=90.0, description="Latitude of the search centre"),
    lng: float = Query(..., ge=-180.0, le=180.0, description="Longitude of the search centre"),
    radius_km: float = Query(50.0, gt=0.0, le=500.0, description="Search radius in km"),
    status_filter: Optional[str] = Query(None, alias="status"),
) -> dict:
    """
    Return upcoming tournaments whose venue GPS pin is within radius_km of the
    given lat/lng.  Only tournaments that were created with a latitude+longitude
    are returned.  Results include a `distance_km` field (haversine, rounded to
    2 decimal places) and are ordered nearest-first.
    """
    rows, total = await svc.get_nearby_tournaments(
        db, lat, lng, radius_km, params, status_filter=status_filter
    )
    pages = (total + params.page_size - 1) // params.page_size if total else 0
    return ok({
        "items": [TournamentNearbyResult.model_validate(r).model_dump() for r in rows],
        "total": total,
        "page": params.page,
        "page_size": params.page_size,
        "pages": pages,
    })


@router.get("/my-hosted", status_code=status.HTTP_200_OK)
async def get_my_hosted_tournaments(
    params: Annotated[PageParams, Depends()],
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Return all tournaments the authenticated user has created, newest first."""
    items, total = await svc.get_my_hosted_tournaments(db, current_user.id, params)
    return paginate(
        [TournamentResponse.model_validate(t).model_dump() for t in items],
        total,
        params,
    )


@router.get("/my-joined", status_code=status.HTTP_200_OK)
async def get_my_joined_tournaments(
    params: Annotated[PageParams, Depends()],
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Return tournaments the authenticated user has joined (REGISTERED status)."""
    items, total = await svc.get_my_joined_tournaments(db, current_user.id, params)
    return paginate(
        [TournamentResponse.model_validate(t).model_dump() for t in items],
        total,
        params,
    )


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
