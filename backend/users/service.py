import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from common.exceptions import NotFoundError
from users.models import PlayerProfile, User
from users.schemas import PlayerProfileUpdate


async def get_my_profile(db: AsyncSession, user_id: uuid.UUID) -> tuple[User, PlayerProfile | None]:
    result = await db.execute(select(User).where(User.id == user_id, User.deleted_at.is_(None)))
    user = result.scalar_one_or_none()
    if user is None:
        raise NotFoundError("User not found")

    result = await db.execute(select(PlayerProfile).where(PlayerProfile.user_id == user_id))
    profile = result.scalar_one_or_none()
    return user, profile


async def upsert_profile(
    db: AsyncSession, user_id: uuid.UUID, data: PlayerProfileUpdate
) -> PlayerProfile:
    result = await db.execute(select(PlayerProfile).where(PlayerProfile.user_id == user_id))
    profile = result.scalar_one_or_none()

    if profile is None:
        profile = PlayerProfile(
            user_id=user_id,
            display_name=data.display_name or "",
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

    await db.flush()
    return profile


async def get_public_profile(
    db: AsyncSession, user_id: uuid.UUID
) -> tuple[User, PlayerProfile | None]:
    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise NotFoundError("User not found")

    result = await db.execute(select(PlayerProfile).where(PlayerProfile.user_id == user_id))
    profile = result.scalar_one_or_none()
    return user, profile
