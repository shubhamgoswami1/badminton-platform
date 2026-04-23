import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, Float, ForeignKey, Text
from sqlalchemy.dialects.postgresql import DOUBLE_PRECISION, TIMESTAMPTZ, UUID
from sqlalchemy.orm import Mapped, mapped_column

from common.models import TimestampMixin, UUIDPrimaryKeyMixin
from database import Base

_RELIABILITY_DEFAULT = 5.0


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "users"

    phone_number: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    is_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)


class PlayerProfile(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """
    One-to-one with User. Created lazily on first profile update.

    Fields:
      display_name     – required; used for search and display
      city             – free-text city string; used for city-based discovery
      skill_level      – SkillLevel enum value stored as text
      play_style       – PlayStyle enum value stored as text
      bio              – free-text self-description
      latitude         – optional GPS latitude; stored for future radius search
      longitude        – optional GPS longitude; stored for future radius search
      reliability_score– 0.0–5.0, default 5.0; degrades on confirmed no-shows
      rating           – 0.0–10.0, nullable; manually set or computed from results
    """

    __tablename__ = "player_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    display_name: Mapped[str] = mapped_column(Text, nullable=False)
    city: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    skill_level: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    play_style: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    bio: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Location — optional; used for radius search when GPS is enabled (post-MVP)
    latitude: Mapped[Optional[float]] = mapped_column(
        DOUBLE_PRECISION, nullable=True
    )
    longitude: Mapped[Optional[float]] = mapped_column(
        DOUBLE_PRECISION, nullable=True
    )

    # Scoring
    reliability_score: Mapped[float] = mapped_column(
        Float, nullable=False, default=_RELIABILITY_DEFAULT
    )
    rating: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
