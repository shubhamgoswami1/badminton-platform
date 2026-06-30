import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from admin.models import AdminLog
from admin.schemas import AdminAction, AdminTargetType
from common.exceptions import ConflictError, NotFoundError
from common.pagination import PageParams
from tournaments.models import Match, Tournament
from users.models import User


def _now() -> datetime:
    return datetime.now(timezone.utc)


async def _write_log(
    db: AsyncSession,
    *,
    admin_id: uuid.UUID,
    action: str,
    target_type: str,
    target_id: uuid.UUID,
    notes: Optional[str],
) -> AdminLog:
    entry = AdminLog(
        admin_id=admin_id,
        action=action,
        target_type=target_type,
        target_id=target_id,
        notes=notes,
    )
    db.add(entry)
    return entry


async def ban_user(
    db: AsyncSession,
    admin_id: uuid.UUID,
    target_user_id: uuid.UUID,
    notes: Optional[str],
) -> User:
    result = await db.execute(
        select(User).where(User.id == target_user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise NotFoundError("User not found")
    if user.id == admin_id:
        raise ConflictError("Admin cannot ban themselves")

    user.is_banned = True
    await _write_log(
        db,
        admin_id=admin_id,
        action=AdminAction.BAN_USER,
        target_type=AdminTargetType.USER,
        target_id=target_user_id,
        notes=notes,
    )
    await db.commit()
    await db.refresh(user)
    return user


async def unban_user(
    db: AsyncSession,
    admin_id: uuid.UUID,
    target_user_id: uuid.UUID,
    notes: Optional[str],
) -> User:
    result = await db.execute(
        select(User).where(User.id == target_user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise NotFoundError("User not found")

    user.is_banned = False
    await _write_log(
        db,
        admin_id=admin_id,
        action=AdminAction.UNBAN_USER,
        target_type=AdminTargetType.USER,
        target_id=target_user_id,
        notes=notes,
    )
    await db.commit()
    await db.refresh(user)
    return user


async def delete_tournament(
    db: AsyncSession,
    admin_id: uuid.UUID,
    tournament_id: uuid.UUID,
    notes: Optional[str],
) -> Tournament:
    result = await db.execute(
        select(Tournament).where(
            Tournament.id == tournament_id,
            Tournament.deleted_at.is_(None),
        )
    )
    tournament = result.scalar_one_or_none()
    if tournament is None:
        raise NotFoundError("Tournament not found")

    # Refuse to hard-delete a live tournament with matches in progress.
    in_progress = await db.execute(
        select(Match).where(
            Match.tournament_id == tournament_id,
            Match.status == "IN_PROGRESS",
        )
    )
    if in_progress.first() is not None:
        raise ConflictError(
            "Cannot delete a tournament with matches currently in progress"
        )

    tournament.deleted_at = _now()
    await _write_log(
        db,
        admin_id=admin_id,
        action=AdminAction.DELETE_TOURNAMENT,
        target_type=AdminTargetType.TOURNAMENT,
        target_id=tournament_id,
        notes=notes,
    )
    await db.commit()
    await db.refresh(tournament)
    return tournament


async def list_logs(
    db: AsyncSession,
    params: PageParams,
    action_filter: Optional[str] = None,
) -> tuple[list[AdminLog], int]:
    from sqlalchemy import func

    q = select(AdminLog)
    if action_filter:
        q = q.where(AdminLog.action == action_filter)

    total_q = select(func.count()).select_from(q.subquery())
    total = (await db.execute(total_q)).scalar_one()

    q = q.order_by(AdminLog.created_at.desc()).offset(params.offset).limit(params.limit)
    rows = (await db.execute(q)).scalars().all()
    return list(rows), total
