import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

import users.service as users_service
from common.dependencies import get_current_user
from common.response import ok
from database import get_db
from users.models import User
from users.schemas import PlayerProfileResponse, PlayerProfileUpdate, UserResponse, UserWithProfileResponse

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", status_code=status.HTTP_200_OK)
async def get_me(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    user, profile = await users_service.get_my_profile(db, current_user.id)
    return ok(UserWithProfileResponse(
        user=UserResponse.model_validate(user),
        profile=PlayerProfileResponse.model_validate(profile) if profile else None,
    ).model_dump())


@router.put("/me/profile", status_code=status.HTTP_200_OK)
async def update_my_profile(
    body: PlayerProfileUpdate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    profile = await users_service.upsert_profile(db, current_user.id, body)
    return ok(PlayerProfileResponse.model_validate(profile).model_dump())


@router.get("/{user_id}/profile", status_code=status.HTTP_200_OK)
async def get_user_profile(
    user_id: uuid.UUID,
    _current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    _user, profile = await users_service.get_public_profile(db, user_id)
    if profile is None:
        return ok(None)
    return ok(PlayerProfileResponse.model_validate(profile).model_dump())
