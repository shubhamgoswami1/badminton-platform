import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

import scores.service as svc
from common.dependencies import get_current_user
from common.response import ok
from database import get_db
from scores.schemas import MatchScoreResponse, SetScoreResponse, SubmitScoreRequest
from users.models import User

router = APIRouter(prefix="/matches", tags=["scores"])


@router.post("/{match_id}/score", status_code=status.HTTP_200_OK)
async def submit_score(
    match_id: uuid.UUID,
    body: SubmitScoreRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    match = await svc.submit_score(db, match_id, current_user.id, body)
    _, score_rows = await svc.get_match_scores(db, match_id)
    return ok(
        MatchScoreResponse(
            match_id=match.id,
            status=match.status,
            winner_participant_id=match.winner_participant_id,
            sets=[SetScoreResponse.model_validate(s) for s in score_rows],
        ).model_dump()
    )


@router.get("/{match_id}/score", status_code=status.HTTP_200_OK)
async def get_score(
    match_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    match, score_rows = await svc.get_match_scores(db, match_id)
    return ok(
        MatchScoreResponse(
            match_id=match.id,
            status=match.status,
            winner_participant_id=match.winner_participant_id,
            sets=[SetScoreResponse.model_validate(s) for s in score_rows],
        ).model_dump()
    )


@router.post("/{match_id}/walkover", status_code=status.HTTP_200_OK)
async def record_walkover(
    match_id: uuid.UUID,
    body: dict,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    winner_id = uuid.UUID(body["winner_participant_id"])
    match = await svc.record_walkover(db, match_id, current_user.id, winner_id)
    return ok({"match_id": str(match.id), "status": match.status, "winner_participant_id": str(match.winner_participant_id)})
