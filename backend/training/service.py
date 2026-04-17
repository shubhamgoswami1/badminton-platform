"""Training log and goal service — P8/P9."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from common.enums import GoalStatus
from common.exceptions import ForbiddenError, NotFoundError
from common.pagination import PageParams
from training.models import TrainingGoal, TrainingLog
from training.schemas import TrainingGoalCreate, TrainingGoalUpdate, TrainingLogCreate, TrainingLogUpdate


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Training Logs ─────────────────────────────────────────────


async def create_log(db: AsyncSession, user_id: uuid.UUID, data: TrainingLogCreate) -> TrainingLog:
    log = TrainingLog(
        user_id=user_id,
        session_type=data.session_type.value,
        duration_minutes=data.duration_minutes,
        notes=data.notes,
        logged_at=data.logged_at or _now(),
    )
    db.add(log)
    await db.flush()
    return log


async def get_log(db: AsyncSession, log_id: uuid.UUID, user_id: uuid.UUID) -> TrainingLog:
    result = await db.execute(select(TrainingLog).where(TrainingLog.id == log_id))
    log = result.scalar_one_or_none()
    if log is None:
        raise NotFoundError("Training log not found")
    if log.user_id != user_id:
        raise ForbiddenError("Access denied")
    return log


async def list_logs(
    db: AsyncSession, user_id: uuid.UUID, params: PageParams
) -> tuple[list[TrainingLog], int]:
    from sqlalchemy import func
    q = select(TrainingLog).where(TrainingLog.user_id == user_id)
    total = (await db.execute(select(func.count()).select_from(q.subquery()))).scalar_one()
    q = q.order_by(TrainingLog.logged_at.desc()).offset(params.offset).limit(params.limit)
    result = await db.execute(q)
    return list(result.scalars().all()), total


async def update_log(
    db: AsyncSession, log_id: uuid.UUID, user_id: uuid.UUID, data: TrainingLogUpdate
) -> TrainingLog:
    log = await get_log(db, log_id, user_id)
    if data.session_type is not None:
        log.session_type = data.session_type.value
    if data.duration_minutes is not None:
        log.duration_minutes = data.duration_minutes
    if data.notes is not None:
        log.notes = data.notes
    if data.logged_at is not None:
        log.logged_at = data.logged_at
    await db.flush()
    return log


async def delete_log(db: AsyncSession, log_id: uuid.UUID, user_id: uuid.UUID) -> None:
    log = await get_log(db, log_id, user_id)
    await db.delete(log)
    await db.flush()


# ── Training Goals ────────────────────────────────────────────


async def create_goal(db: AsyncSession, user_id: uuid.UUID, data: TrainingGoalCreate) -> TrainingGoal:
    goal = TrainingGoal(
        user_id=user_id,
        title=data.title,
        description=data.description,
        target_date=data.target_date,
        status=GoalStatus.ACTIVE.value,
    )
    db.add(goal)
    await db.flush()
    return goal


async def get_goal(db: AsyncSession, goal_id: uuid.UUID, user_id: uuid.UUID) -> TrainingGoal:
    result = await db.execute(select(TrainingGoal).where(TrainingGoal.id == goal_id))
    goal = result.scalar_one_or_none()
    if goal is None:
        raise NotFoundError("Training goal not found")
    if goal.user_id != user_id:
        raise ForbiddenError("Access denied")
    return goal


async def list_goals(db: AsyncSession, user_id: uuid.UUID, params: PageParams) -> tuple[list[TrainingGoal], int]:
    from sqlalchemy import func
    q = select(TrainingGoal).where(TrainingGoal.user_id == user_id)
    total = (await db.execute(select(func.count()).select_from(q.subquery()))).scalar_one()
    q = q.order_by(TrainingGoal.created_at.desc()).offset(params.offset).limit(params.limit)
    result = await db.execute(q)
    return list(result.scalars().all()), total


async def update_goal(
    db: AsyncSession, goal_id: uuid.UUID, user_id: uuid.UUID, data: TrainingGoalUpdate
) -> TrainingGoal:
    goal = await get_goal(db, goal_id, user_id)
    if data.title is not None:
        goal.title = data.title
    if data.description is not None:
        goal.description = data.description
    if data.target_date is not None:
        goal.target_date = data.target_date
    if data.status is not None:
        goal.status = data.status.value
        if data.status == GoalStatus.ACHIEVED:
            goal.completed_at = _now()
    await db.flush()
    return goal


async def delete_goal(db: AsyncSession, goal_id: uuid.UUID, user_id: uuid.UUID) -> None:
    goal = await get_goal(db, goal_id, user_id)
    await db.delete(goal)
    await db.flush()
