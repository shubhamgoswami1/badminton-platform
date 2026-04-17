from typing import Annotated, Optional

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

import discovery.service as svc
from common.dependencies import get_current_user
from common.pagination import PageParams, paginate
from common.response import ok
from database import get_db
from discovery.schemas import PlayerDiscoveryResponse, TournamentDiscoveryResponse, VenueCreate, VenueResponse
from users.models import User

router = APIRouter(prefix="/discovery", tags=["discovery"])


@router.get("/players", status_code=status.HTTP_200_OK)
async def discover_players(
    params: Annotated[PageParams, Depends()],
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    city: Optional[str] = Query(None),
    skill_level: Optional[str] = Query(None),
    play_style: Optional[str] = Query(None),
) -> dict:
    items, total = await svc.discover_players(db, params, city=city, skill_level=skill_level, play_style=play_style)
    return paginate(
        [PlayerDiscoveryResponse(
            user_id=p.user_id,
            display_name=p.display_name,
            city=p.city,
            skill_level=p.skill_level,
            play_style=p.play_style,
            bio=p.bio,
        ).model_dump() for p in items],
        total, params,
    )


@router.get("/tournaments", status_code=status.HTTP_200_OK)
async def discover_tournaments(
    params: Annotated[PageParams, Depends()],
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    city: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    format: Optional[str] = Query(None),
) -> dict:
    items, total = await svc.discover_tournaments(db, params, city=city, status=status, format=format)
    return paginate(
        [TournamentDiscoveryResponse.model_validate(t).model_dump() for t in items],
        total, params,
    )


@router.get("/venues", status_code=status.HTTP_200_OK)
async def list_venues(
    params: Annotated[PageParams, Depends()],
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    city: Optional[str] = Query(None),
) -> dict:
    items, total = await svc.list_venues(db, params, city=city)
    return paginate([VenueResponse.model_validate(v).model_dump() for v in items], total, params)


@router.post("/venues", status_code=status.HTTP_201_CREATED)
async def submit_venue(
    body: VenueCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    venue = await svc.submit_venue(db, current_user.id, body)
    return ok(VenueResponse.model_validate(venue).model_dump())
