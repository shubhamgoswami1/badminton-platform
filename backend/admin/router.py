"""
Admin router — P12 / admin module.

Endpoints
─────────
  POST /admin/ban-user          → ban a user account
  POST /admin/unban-user        → lift a ban
  POST /admin/delete-tournament → soft-delete a tournament (validated)
  GET  /admin/logs              → paginated audit log

All endpoints require admin privileges (is_admin=True on the caller's User row).
"""

from typing import Annotated, Optional

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

import admin.service as svc
from admin.schemas import (
    AdminLogResponse,
    BanUserRequest,
    DeleteTournamentRequest,
    UnbanUserRequest,
)
from common.dependencies import get_current_admin
from common.pagination import PageParams, paginate
from common.response import ok
from database import get_db
from users.models import User

router = APIRouter(prefix="/admin", tags=["admin"])


@router.post("/ban-user", status_code=status.HTTP_200_OK)
async def ban_user(
    body: BanUserRequest,
    admin: Annotated[User, Depends(get_current_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Ban a user account.  Banned users receive 403 on all protected endpoints.
    Idempotent: banning an already-banned user is accepted without error.
    """
    user = await svc.ban_user(db, admin.id, body.user_id, body.notes)
    return ok({"user_id": str(user.id), "is_banned": user.is_banned})


@router.post("/unban-user", status_code=status.HTTP_200_OK)
async def unban_user(
    body: UnbanUserRequest,
    admin: Annotated[User, Depends(get_current_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Lift a ban.  Idempotent: unbanning a non-banned user is accepted."""
    user = await svc.unban_user(db, admin.id, body.user_id, body.notes)
    return ok({"user_id": str(user.id), "is_banned": user.is_banned})


@router.post("/delete-tournament", status_code=status.HTTP_200_OK)
async def delete_tournament(
    body: DeleteTournamentRequest,
    admin: Annotated[User, Depends(get_current_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Soft-delete a tournament.

    Rejected (409) if the tournament has any match currently IN_PROGRESS.
    All other statuses (DRAFT, REGISTRATION_OPEN/CLOSED, COMPLETED, CANCELLED)
    are accepted.
    """
    tournament = await svc.delete_tournament(
        db, admin.id, body.tournament_id, body.notes
    )
    return ok({
        "tournament_id": str(tournament.id),
        "deleted_at": tournament.deleted_at.isoformat() if tournament.deleted_at else None,
    })


@router.get("/logs", status_code=status.HTTP_200_OK)
async def get_logs(
    admin: Annotated[User, Depends(get_current_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    params: Annotated[PageParams, Depends()],
    action: Optional[str] = Query(
        default=None,
        description="Filter by action type: BAN_USER, UNBAN_USER, DELETE_TOURNAMENT",
    ),
) -> dict:
    """Paginated admin audit log, newest first."""
    logs, total = await svc.list_logs(db, params, action)
    return paginate(
        [AdminLogResponse.model_validate(log).model_dump() for log in logs],
        total,
        params,
    )
