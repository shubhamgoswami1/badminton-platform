import math
import uuid
from typing import Annotated, Optional

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

import users.service as users_service
from common.dependencies import get_current_user
from common.enums import PlayStyle, SkillLevel
from common.response import ok
from database import get_db
from users.models import User
from users.schemas import (
    PlayerProfileResponse,
    PlayerProfileUpdate,
    PlayerSearchParams,
    PlayerSearchResponse,
    PlayerSearchResult,
    UserResponse,
    UserWithProfileResponse,
)

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", status_code=status.HTTP_200_OK)
async def get_me(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Return the authenticated user and their player profile (null if not yet created)."""
    user, profile = await users_service.get_my_profile(db, current_user.id)
    return ok(
        UserWithProfileResponse(
            user=UserResponse.model_validate(user),
            profile=PlayerProfileResponse.model_validate(profile) if profile else None,
        ).model_dump()
    )


@router.put("/me/profile", status_code=status.HTTP_200_OK)
async def update_my_profile(
    body: PlayerProfileUpdate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Create or partially update the authenticated user's player profile.
    All fields are optional — only provided fields are written.
    Banned users are rejected by get_current_user (deleted_at check).
    """
    profile = await users_service.upsert_profile(db, current_user.id, body)
    return ok(PlayerProfileResponse.model_validate(profile).model_dump())


@router.get("/search", status_code=status.HTTP_200_OK)
async def search_players(
    _current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: Optional[str] = Query(None, description="Substring search on name or city"),
    skill_level: Optional[SkillLevel] = Query(None),
    play_style: Optional[PlayStyle] = Query(None),
    min_rating: Optional[float] = Query(None, ge=0.0, le=10.0),
    max_rating: Optional[float] = Query(None, ge=0.0, le=10.0),
    lat: Optional[float] = Query(None, ge=-90.0, le=90.0),
    lng: Optional[float] = Query(None, ge=-180.0, le=180.0),
    radius_km: Optional[float] = Query(None, gt=0.0, le=500.0),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
) -> dict:
    """
    Search player profiles.

    Filters (all optional, AND-combined):
    - q           : case-insensitive substring on display_name or city
    - skill_level : BEGINNER | INTERMEDIATE | ADVANCED | PROFESSIONAL
    - play_style  : SINGLES | DOUBLES | BOTH
    - min_rating  : lower bound on numeric rating (0–10); profiles without
                    a rating are excluded when either bound is set
    - max_rating  : upper bound on numeric rating
    - lat + lng + radius_km : bounding-box radius filter; all three required
                              together; profiles without GPS coords are excluded

    Results ordered by reliability_score DESC, display_name ASC.

    Sample request:
      GET /api/v1/users/search?q=alice&skill_level=ADVANCED&min_rating=7.0&page=1

    Sample response:
      {
        "data": {
          "items": [
            {
              "user_id": "...",
              "display_name": "Alice",
              "city": "Mumbai",
              "skill_level": "ADVANCED",
              "play_style": "SINGLES",
              "reliability_score": 4.8,
              "rating": 8.2
            }
          ],
          "total": 1,
          "page": 1,
          "page_size": 20,
          "pages": 1
        },
        "error": null,
        "meta": {}
      }
    """
    params = PlayerSearchParams(
        q=q,
        skill_level=skill_level,
        play_style=play_style,
        min_rating=min_rating,
        max_rating=max_rating,
        lat=lat,
        lng=lng,
        radius_km=radius_km,
        page=page,
        page_size=page_size,
    )
    profiles, total = await users_service.search_players(db, params)
    pages = math.ceil(total / page_size) if total else 0
    return ok(
        PlayerSearchResponse(
            items=[PlayerSearchResult.model_validate(p) for p in profiles],
            total=total,
            page=page,
            page_size=page_size,
            pages=pages,
        ).model_dump()
    )


@router.get("/{user_id}/profile", status_code=status.HTTP_200_OK)
async def get_user_profile(
    user_id: uuid.UUID,
    _current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Return public profile for any user. Returns null data if profile not yet created."""
    _user, profile = await users_service.get_public_profile(db, user_id)
    if profile is None:
        return ok(None)
    return ok(PlayerProfileResponse.model_validate(profile).model_dump())
