"""Discovery service — P10."""

import uuid
from typing import Optional

from sqlalchemy import func, literal, select
from sqlalchemy.ext.asyncio import AsyncSession

from common.pagination import PageParams
from discovery.models import Venue
from discovery.schemas import PlayerDiscoveryResponse, VenueCreate
from tournaments.models import Tournament
from users.models import PlayerProfile, User

_EARTH_RADIUS_KM = 6371.0


def _haversine_km(lat: float, lng: float, lat_col, lng_col):
    """SQLAlchemy expression for great-circle distance in km (haversine)."""
    dlat = func.radians(lat_col - lat)
    dlng = func.radians(lng_col - lng)
    a = (
        func.pow(func.sin(dlat / 2), 2)
        + func.cos(func.radians(literal(lat)))
        * func.cos(func.radians(lat_col))
        * func.pow(func.sin(dlng / 2), 2)
    )
    return _EARTH_RADIUS_KM * 2 * func.asin(func.sqrt(a))


def _base_player_query(
    city: Optional[str],
    skill_level: Optional[str],
    play_style: Optional[str],
    q: Optional[str],
    elo_min: Optional[float],
    elo_max: Optional[float],
):
    """Build the shared filter predicates for player search."""
    stmt = (
        select(PlayerProfile)
        .join(User, User.id == PlayerProfile.user_id)
        .where(User.deleted_at.is_(None))
    )
    if city:
        stmt = stmt.where(func.lower(PlayerProfile.city) == city.lower())
    if skill_level:
        stmt = stmt.where(PlayerProfile.skill_level == skill_level)
    if play_style:
        stmt = stmt.where(PlayerProfile.play_style == play_style)
    if q:
        # Prefix match; benefits from functional index on lower(display_name).
        stmt = stmt.where(
            func.lower(PlayerProfile.display_name).like(f"{q.lower()}%")
        )
    if elo_min is not None:
        stmt = stmt.where(PlayerProfile.elo_rating >= elo_min)
    if elo_max is not None:
        stmt = stmt.where(PlayerProfile.elo_rating <= elo_max)
    return stmt


def _profile_to_response(p: PlayerProfile, distance_km: Optional[float] = None) -> PlayerDiscoveryResponse:
    return PlayerDiscoveryResponse(
        user_id=p.user_id,
        display_name=p.display_name,
        city=p.city,
        skill_level=p.skill_level,
        play_style=p.play_style,
        bio=p.bio,
        elo_rating=p.elo_rating,
        matches_played=p.matches_played,
        wins=p.wins,
        losses=p.losses,
        reliability_score=p.reliability_score,
        distance_km=distance_km,
    )


async def discover_players(
    db: AsyncSession,
    params: PageParams,
    city: Optional[str] = None,
    skill_level: Optional[str] = None,
    play_style: Optional[str] = None,
    q: Optional[str] = None,
    elo_min: Optional[float] = None,
    elo_max: Optional[float] = None,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    radius_km: Optional[float] = None,
) -> tuple[list[PlayerDiscoveryResponse], int]:
    use_location = lat is not None and lng is not None and radius_km is not None

    if use_location:
        return await _discover_players_by_location(
            db, params,
            city=city, skill_level=skill_level, play_style=play_style,
            q=q, elo_min=elo_min, elo_max=elo_max,
            lat=lat, lng=lng, radius_km=radius_km,
        )

    # ── Non-location path ────────────────────────────────────────────────────
    stmt = _base_player_query(city, skill_level, play_style, q, elo_min, elo_max)
    total = (await db.execute(
        select(func.count()).select_from(stmt.subquery())
    )).scalar_one()

    ordered = (
        stmt
        .order_by(PlayerProfile.elo_rating.desc().nullslast(), PlayerProfile.display_name)
        .offset(params.offset)
        .limit(params.limit)
    )
    profiles = list((await db.execute(ordered)).scalars().all())
    return [_profile_to_response(p) for p in profiles], total


async def _discover_players_by_location(
    db: AsyncSession,
    params: PageParams,
    city: Optional[str],
    skill_level: Optional[str],
    play_style: Optional[str],
    q: Optional[str],
    elo_min: Optional[float],
    elo_max: Optional[float],
    lat: float,
    lng: float,
    radius_km: float,
) -> tuple[list[PlayerDiscoveryResponse], int]:
    dist_expr = _haversine_km(
        lat, lng, PlayerProfile.latitude, PlayerProfile.longitude
    ).cast(float).label("distance_km")

    # Bounding-box pre-filter reduces rows before exact haversine.
    deg = radius_km / 111.0
    stmt = (
        _base_player_query(city, skill_level, play_style, q, elo_min, elo_max)
        .add_columns(dist_expr)
        .where(
            PlayerProfile.latitude.isnot(None),
            PlayerProfile.longitude.isnot(None),
            PlayerProfile.latitude.between(lat - deg, lat + deg),
            PlayerProfile.longitude.between(lng - deg, lng + deg),
        )
    )
    sub = stmt.subquery()
    within_radius = sub.c.distance_km <= radius_km

    total = (await db.execute(
        select(func.count()).select_from(sub).where(within_radius)
    )).scalar_one()

    rows = (await db.execute(
        select(sub)
        .where(within_radius)
        .order_by(sub.c.distance_km)
        .offset(params.offset)
        .limit(params.limit)
    )).mappings().all()

    items = []
    for row in rows:
        # Reconstruct from column names (mappings returns a dict-like view).
        p = PlayerProfile(
            user_id=row["user_id"],
            display_name=row["display_name"],
            city=row["city"],
            skill_level=row["skill_level"],
            play_style=row["play_style"],
            bio=row["bio"],
            elo_rating=row["elo_rating"],
            matches_played=row["matches_played"],
            wins=row["wins"],
            losses=row["losses"],
            reliability_score=row["reliability_score"],
        )
        items.append(_profile_to_response(p, distance_km=round(float(row["distance_km"]), 2)))
    return items, total


# ── Tournaments ───────────────────────────────────────────────────────────────


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


# ── Venues ────────────────────────────────────────────────────────────────────


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
