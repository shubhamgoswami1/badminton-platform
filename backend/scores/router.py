"""
Match scoring and detail router — P6.

Endpoints
─────────
  GET  /matches/{id}              → full match detail + scores
  POST /matches/{id}/score        → submit scores + complete (one-shot)
  GET  /matches/{id}/score        → get scores (legacy alias)
  POST /matches/{id}/update-score → save scores, transition to IN_PROGRESS
  POST /matches/{id}/complete     → complete match, apply Elo
  POST /matches/{id}/walkover     → record walkover (organiser only)
"""

import uuid
from typing import Annotated, Optional

from fastapi import APIRouter, Depends, status
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

import scores.service as svc
from common.dependencies import get_current_user
from common.exceptions import SyncConflictError
from common.response import ok
from database import get_db
from fastapi import Query
from scores.schemas import (
    CompleteMatchRequest,
    MatchDetailResponse,
    MatchScoreResponse,
    MyMatchItem,
    SetScoreResponse,
    SubmitScoreRequest,
    UpdateScoreRequest,
)
from users.models import User

router = APIRouter(prefix="/matches", tags=["scores"])


def _sync_conflict_response(exc: SyncConflictError) -> JSONResponse:
    """
    Build the 409 SYNC_CONFLICT response.

    Shape
    ─────
    {
      "data": {
        "server_version": <int>,
        "server_updated_at": "<ISO-8601>",
        "server_status": "<str>",
        "sets": [...]
      },
      "error": {
        "code": "SYNC_CONFLICT",
        "message": "<str>",
        "conflict_type": "STALE_UPDATE | MATCH_COMPLETED"
      }
    }

    The client uses `data` to update its local state before retrying.
    """
    return JSONResponse(
        status_code=409,
        content={
            "data": {
                "server_version": exc.server_version,
                "server_updated_at": exc.server_updated_at.isoformat()
                if exc.server_updated_at
                else None,
                "server_status": exc.server_status,
                "sets": exc.sets,
            },
            "error": {
                "code": "SYNC_CONFLICT",
                "message": exc.message,
                "conflict_type": exc.conflict_type,
            },
        },
    )


def _detail_response(match, score_rows) -> dict:
    return ok(
        MatchDetailResponse(
            match_id=match.id,
            tournament_id=match.tournament_id,
            round=match.round,
            match_number=match.match_number,
            side_a_participant_id=match.side_a_participant_id,
            side_b_participant_id=match.side_b_participant_id,
            winner_participant_id=match.winner_participant_id,
            status=match.status,
            elo_applied=match.elo_applied,
            version=match.version,
            scheduled_at=match.scheduled_at,
            completed_at=match.completed_at,
            updated_at=match.updated_at,
            sets=[SetScoreResponse.model_validate(s) for s in score_rows],
        ).model_dump()
    )


# ── GET /matches/my ───────────────────────────────────────────────────────────
# IMPORTANT: this static route MUST be registered before /{match_id} so that
# FastAPI does not treat the literal string "my" as a UUID match_id.

@router.get("/my", status_code=status.HTTP_200_OK)
async def get_my_matches(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    status: Optional[str] = Query(
        default=None,
        description=(
            "Comma-separated match statuses to filter by. "
            "E.g. PENDING,IN_PROGRESS  or  COMPLETED"
        ),
    ),
) -> dict:
    """
    Return all matches where the authenticated user is a participant
    (side A or B), across every non-deleted tournament.

    Includes `tournament_title` and `organiser_id` for client context.
    Optional `?status=PENDING,IN_PROGRESS` filter.
    """
    status_filter: list[str] | None = None
    if status:
        status_filter = [s.strip().upper() for s in status.split(",") if s.strip()]

    items = await svc.get_my_matches(db, current_user.id, status_filter)
    return ok([MyMatchItem(**item).model_dump() for item in items])


# ── GET /matches/{id} ──────────────────────────────────────────────────────────

@router.get("/{match_id}", status_code=status.HTTP_200_OK)
async def get_match(
    match_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Return full match detail including all recorded set scores."""
    match, score_rows = await svc.get_match_detail(db, match_id)
    return _detail_response(match, score_rows)


# ── POST /matches/{id}/update-score ───────────────────────────────────────────

@router.post("/{match_id}/update-score", status_code=status.HTTP_200_OK)
async def update_score(
    match_id: uuid.UUID,
    body: UpdateScoreRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Save set scores without completing the match.
    Transitions PENDING → IN_PROGRESS on first call.

    Optionally supply `client_updated_at` (the match.updated_at the client
    last fetched) to enable offline-sync conflict detection.
    """
    try:
        match, score_rows = await svc.update_score(db, match_id, current_user.id, body)
    except SyncConflictError as exc:
        return _sync_conflict_response(exc)
    return _detail_response(match, score_rows)


# ── POST /matches/{id}/complete ───────────────────────────────────────────────

@router.post("/{match_id}/complete", status_code=status.HTTP_200_OK)
async def complete_match(
    match_id: uuid.UUID,
    body: CompleteMatchRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Complete a match and apply Elo ratings.
    Optionally replaces stored scores if sets are provided.

    Idempotent: retrying with the same winner after a network timeout returns
    200 with the current server state rather than a conflict error.
    """
    try:
        match, score_rows = await svc.complete_match(db, match_id, current_user.id, body)
    except SyncConflictError as exc:
        return _sync_conflict_response(exc)
    return _detail_response(match, score_rows)


# ── POST /matches/{id}/score (one-shot, kept for compatibility) ────────────────

@router.post("/{match_id}/score", status_code=status.HTTP_200_OK)
async def submit_score(
    match_id: uuid.UUID,
    body: SubmitScoreRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Submit all set scores and complete the match in one request."""
    try:
        match, score_rows = await svc.submit_score(db, match_id, current_user.id, body)
    except SyncConflictError as exc:
        return _sync_conflict_response(exc)
    return ok(
        MatchScoreResponse(
            match_id=match.id,
            status=match.status,
            winner_participant_id=match.winner_participant_id,
            sets=[SetScoreResponse.model_validate(s) for s in score_rows],
        ).model_dump()
    )


# ── GET /matches/{id}/score (legacy alias) ────────────────────────────────────

@router.get("/{match_id}/score", status_code=status.HTTP_200_OK)
async def get_score(
    match_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Get the current scores for a match (legacy endpoint)."""
    match, score_rows = await svc.get_match_scores(db, match_id)
    return ok(
        MatchScoreResponse(
            match_id=match.id,
            status=match.status,
            winner_participant_id=match.winner_participant_id,
            sets=[SetScoreResponse.model_validate(s) for s in score_rows],
        ).model_dump()
    )


# ── POST /matches/{id}/walkover ───────────────────────────────────────────────

@router.post("/{match_id}/walkover", status_code=status.HTTP_200_OK)
async def record_walkover(
    match_id: uuid.UUID,
    body: dict,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Record a walkover (organiser only). No Elo is applied for walkovers."""
    winner_id = uuid.UUID(body["winner_participant_id"])
    match = await svc.record_walkover(db, match_id, current_user.id, winner_id)
    return ok({
        "match_id": str(match.id),
        "status": match.status,
        "winner_participant_id": str(match.winner_participant_id),
        "version": match.version,
    })
