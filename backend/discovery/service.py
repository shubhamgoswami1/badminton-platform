"""Discovery service — P10."""

import uuid
from typing import Optional

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from common.pagination import PageParams
from discovery.models import Venue
from discovery.schemas import VenueCreate
from tournaments.models import Tournament
from users.models import PlayerProfile, User


async def discover_players(
    db: AsyncSession,
    params: PageParams,
    city: Optional[str] = None,
    skill_level: Optional[str] = None,
    play_style: Optional[str] = None,
) -> tuple[list[PlayerProfile], int]:
    q = (
        select(PlayerProfile)
        .join(User, User.id == PlayerProfile.user_id)
        .where(User.deleted_at.is_(None))
    )
    if city:
        q = q.where(func.lower(PlayerProfile.city) == city.lower())
    if skill_level:
        q = q.where(PlayerProfile.skill_level == skill_level)
    if play_style:
        q = q.where(PlayerProfile.play_style == play_style)

    total = (await db.execute(select(func.count()).select_from(q.subquery()))).scalar_one()
    q = q.order_by(PlayerProfile.display_name).offset(params.offset).limit(params.limit)
    result = await db.execute(q)
    return list(result.scalars().all()), total


async def discover_tournaments(
    db: AsyncSession,
    params: PageParams,
    city: Optional[str] = None,
    status: Optional[str] = None,
    format: Optional[str] = None,
) -> tuple[list[Tournament], int]:
    q = select(Tournament).where(Tournament.deleted_at.is_(None))
    if city:
        q = q.where(func.lower(Tournament.city) == city.lower())
    if status:
        q = q.where(Tournament.status == status)
    if format:
        q = q.where(Tournament.format == format)

    total = (await db.execute(select(func.count()).select_from(q.subquery()))).scalar_one()
    q = q.order_by(Tournament.created_at.desc()).offset(params.offset).limit(params.limit)
    result = await db.execute(q)
    return list(result.scalars().all()), total


async def list_venues(
    db: AsyncSession,
    params: PageParams,
    city: Optional[str] = None,
) -> tuple[list[Venue], int]:
    q = select(Venue)
    if city:
        q = q.where(func.lower(Venue.city) == city.lower())

    total = (await db.execute(select(func.count()).select_from(q.subquery()))).scalar_one()
    q = q.order_by(Venue.name).offset(params.offset).limit(params.limit)
    result = await db.execute(q)
    return list(result.scalars().all()), total


async def submit_venue(
    db: AsyncSession, submitter_id: uuid.UUID, data: VenueCreate
) -> Venue:
    venue = Venue(
        name=data.name,
        city=data.city,
        address=data.address,
        court_count=data.court_count,
        submitted_by=submitter_id,
    )
    db.add(venue)
    await db.flush()
    return venue
