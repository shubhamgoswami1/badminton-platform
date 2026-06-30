"""
Users service — profile CRUD and player search.

Rules:
  - All functions are async and receive an explicit db: AsyncSession.
  - No FastAPI concerns enter this layer.
  - Domain errors are AppError subclasses.
"""

import math
import uuid
from typing import Optional

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from common.exceptions import NotFoundError, ValidationError
from users.models import PlayerProfile, User
from users.schemas import PlayerProfileUpdate, PlayerSearchParams

_RELIABILITY_DEFAULT = 5.0


# ── Profile CRUD ──────────────────────────────────────────────────────────


async def get_my_profile(
    db: AsyncSession, user_id: uuid.UUID
) -> tuple[User, Optional[PlayerProfile]]:
    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise NotFoundError("User not found")

    result = await db.execute(
        select(PlayerProfile).where(PlayerProfile.user_id == user_id)
    )
    return user, result.scalar_one_or_none()


async def upsert_profile(
    db: AsyncSession, user_id: uuid.UUID, data: PlayerProfileUpdate
) -> PlayerProfile:
    """Create or partially update the player profile for user_id."""
    # Validate lat/lng: must be provided together or not at all.
    has_lat = data.latitude is not None
    has_lng = data.longitude is not None
    if has_lat != has_lng:
        raise ValidationError("latitude and longitude must be provided together")

    result = await db.execute(
        select(PlayerProfile).where(PlayerProfile.user_id == user_id)
    )
    profile = result.scalar_one_or_none()

    if profile is None:
        profile = PlayerProfile(
            user_id=user_id,
            display_name=data.display_name or "",
            reliability_score=_RELIABILITY_DEFAULT,
        )
        db.add(profile)

    if data.display_name is not None:
        profile.display_name = data.display_name
    if data.city is not None:
        profile.city = data.city
    if data.skill_level is not None:
        profile.skill_level = data.skill_level.value
    if data.play_style is not None:
        profile.play_style = data.play_style.value
    if data.bio is not None:
        profile.bio = data.bio
    if has_lat:
        profile.latitude = data.latitude
        profile.longitude = data.longitude
    if data.rating is not None:
        profile.rating = data.rating

    await db.flush()
    return profile


async def get_public_profile(
    db: AsyncSession, user_id: uuid.UUID
) -> tuple[User, Optional[PlayerProfile]]:
    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise NotFoundError("User not found")

    result = await db.execute(
        select(PlayerProfile).where(PlayerProfile.user_id == user_id)
    )
    return user, result.scalar_one_or_none()


# ── Player search ─────────────────────────────────────────────────────────


async def search_players(
    db: AsyncSession, params: PlayerSearchParams
) -> tuple[list[PlayerProfile], int]:
    """
    Search player profiles with optional filters:
      - q            : case-insensitive substring on display_name OR city
      - skill_level  : exact enum match
      - play_style   : exact enum match
      - min/max_rating: inclusive range on the rating column (NULLs excluded)
      - lat/lng/radius_km: bounding-box pre-filter when all three are supplied.
                           Full haversine is post-MVP; bounding box is accurate
                           enough within ±500 km for discovery purposes.

    Excludes profiles belonging to soft-deleted users.
    Results are ordered by reliability_score DESC, display_name ASC.
    """
    q = (
        select(PlayerProfile)
        .join(User, User.id == PlayerProfile.user_id)
        .where(User.deleted_at.is_(None))
    )

    # Text search: display_name OR city (case-insensitive substring)
    if params.q and params.q.strip():
        term = f"%{params.q.strip().lower()}%"
        q = q.where(
            or_(
                func.lower(PlayerProfile.display_name).like(term),
                func.lower(PlayerProfile.city).like(term),
            )
        )

    # Skill level filter
    if params.skill_level:
        q = q.where(PlayerProfile.skill_level == params.skill_level.value)

    # Play style filter
    if params.play_style:
        q = q.where(PlayerProfile.play_style == params.play_style.value)

    # Rating range (only considers profiles that have a rating set)
    if params.min_rating is not None:
        q = q.where(
            PlayerProfile.rating.is_not(None),
            PlayerProfile.rating >= params.min_rating,
        )
    if params.max_rating is not None:
        q = q.where(
            PlayerProfile.rating.is_not(None),
            PlayerProfile.rating <= params.max_rating,
        )

    # Location bounding-box filter
    if params.lat is not None and params.lng is not None and params.radius_km is not None:
        lat_delta, lng_delta = _bounding_box_deltas(params.lat, params.radius_km)
        q = q.where(
            PlayerProfile.latitude.is_not(None),
            PlayerProfile.latitude.between(
                params.lat - lat_delta, params.lat + lat_delta
            ),
            PlayerProfile.longitude.between(
                params.lng - lng_delta, params.lng + lng_delta
            ),
        )

    # Total count before pagination
    count_q = select(func.count()).select_from(q.subquery())
    total: int = (await db.execute(count_q)).scalar_one()

    # Ordered, paginated results
    q = (
        q.order_by(PlayerProfile.reliability_score.desc(), PlayerProfile.display_name)
        .offset(params.offset)
        .limit(params.page_size)
    )
    result = await db.execute(q)
    return list(result.scalars().all()), total


# ── Helpers ───────────────────────────────────────────────────────────────


def _bounding_box_deltas(lat: float, radius_km: float) -> tuple[float, float]:
    """
    Return (lat_delta_deg, lng_delta_deg) for a bounding box of radius_km
    centred at lat.  Uses the small-angle approximation; accurate to ~1 % for
    radii up to 500 km.
    """
    lat_delta = radius_km / 111.0
    # cos(lat) shrinks longitude degrees towards the poles
    cos_lat = math.cos(math.radians(lat))
    lng_delta = radius_km / (111.0 * cos_lat) if cos_lat > 1e-6 else 180.0
    return lat_delta, lng_delta
