import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Boolean, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import TIMESTAMPTZ, UUID
from sqlalchemy.orm import Mapped, mapped_column

from common.models import TimestampMixin, UUIDPrimaryKeyMixin
from database import Base


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


class TrainingLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "training_logs"

    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    session_type: Mapped[str] = mapped_column(Text, nullable=False)
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    logged_at: Mapped[datetime] = mapped_column(TIMESTAMPTZ, nullable=False, default=_now_utc)


class TrainingGoal(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "training_goals"

    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    target_date: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="ACTIVE")
    completed_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)
