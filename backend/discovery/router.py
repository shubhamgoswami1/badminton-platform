from typing import Annotated, Optional

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

import discovery.service as svc
from common.dependencies import get_current_user
from common.pagination import PageParams, paginate
from common.response import ok
from database import get_db
from discovery.schemas import TournamentDiscoveryResponse, VenueCreate, VenueResponse
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
    q: Optional[str] = Query(None, description="Prefix search on display name"),
    elo_min: Optional[float] = Query(None, description="Minimum Elo rating"),
    elo_max: Optional[float] = Query(None, description="Maximum Elo rating"),
    lat: Optional[float] = Query(None, description="Latitude for radius search"),
    lng: Optional[float] = Query(None, description="Longitude for radius search"),
    radius_km: Optional[float] = Query(None, description="Search radius in km"),
) -> dict:
    items, total = await svc.discover_players(
        db, params,
        city=city, skill_level=skill_level, play_style=play_style,
        q=q, elo_min=elo_min, elo_max=elo_max,
        lat=lat, lng=lng, radius_km=radius_km,
    )
    # Service already returns PlayerDiscoveryResponse instances.
    return paginate([item.model_dump() for item in items], total, params)


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
