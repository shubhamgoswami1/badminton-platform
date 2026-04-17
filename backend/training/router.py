import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

import training.service as svc
from common.dependencies import get_current_user
from common.pagination import PageParams, paginate
from common.response import ok
from database import get_db
from training.schemas import (
    TrainingGoalCreate,
    TrainingGoalResponse,
    TrainingGoalUpdate,
    TrainingLogCreate,
    TrainingLogResponse,
    TrainingLogUpdate,
)
from users.models import User

router = APIRouter(tags=["training"])


# ── Training Logs ─────────────────────────────────────────────

@router.post("/training/logs", status_code=status.HTTP_201_CREATED)
async def create_log(
    body: TrainingLogCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    log = await svc.create_log(db, current_user.id, body)
    return ok(TrainingLogResponse.model_validate(log).model_dump())


@router.get("/training/logs", status_code=status.HTTP_200_OK)
async def list_logs(
    params: Annotated[PageParams, Depends()],
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    items, total = await svc.list_logs(db, current_user.id, params)
    return paginate([TrainingLogResponse.model_validate(l).model_dump() for l in items], total, params)


@router.get("/training/logs/{log_id}", status_code=status.HTTP_200_OK)
async def get_log(
    log_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    log = await svc.get_log(db, log_id, current_user.id)
    return ok(TrainingLogResponse.model_validate(log).model_dump())


@router.put("/training/logs/{log_id}", status_code=status.HTTP_200_OK)
async def update_log(
    log_id: uuid.UUID,
    body: TrainingLogUpdate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    log = await svc.update_log(db, log_id, current_user.id, body)
    return ok(TrainingLogResponse.model_validate(log).model_dump())


@router.delete("/training/logs/{log_id}", status_code=status.HTTP_200_OK)
async def delete_log(
    log_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    await svc.delete_log(db, log_id, current_user.id)
    return ok({"message": "Log deleted"})


# ── Training Goals ────────────────────────────────────────────

@router.post("/training/goals", status_code=status.HTTP_201_CREATED)
async def create_goal(
    body: TrainingGoalCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    goal = await svc.create_goal(db, current_user.id, body)
    return ok(TrainingGoalResponse.model_validate(goal).model_dump())


@router.get("/training/goals", status_code=status.HTTP_200_OK)
async def list_goals(
    params: Annotated[PageParams, Depends()],
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    items, total = await svc.list_goals(db, current_user.id, params)
    return paginate([TrainingGoalResponse.model_validate(g).model_dump() for g in items], total, params)


@router.get("/training/goals/{goal_id}", status_code=status.HTTP_200_OK)
async def get_goal(
    goal_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    goal = await svc.get_goal(db, goal_id, current_user.id)
    return ok(TrainingGoalResponse.model_validate(goal).model_dump())


@router.put("/training/goals/{goal_id}", status_code=status.HTTP_200_OK)
async def update_goal(
    goal_id: uuid.UUID,
    body: TrainingGoalUpdate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    goal = await svc.update_goal(db, goal_id, current_user.id, body)
    return ok(TrainingGoalResponse.model_validate(goal).model_dump())


@router.delete("/training/goals/{goal_id}", status_code=status.HTTP_200_OK)
async def delete_goal(
    goal_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    await svc.delete_goal(db, goal_id, current_user.id)
    return ok({"message": "Goal deleted"})
