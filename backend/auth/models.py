import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import ForeignKey, Index, Text
from sqlalchemy.dialects.postgresql import TIMESTAMPTZ, UUID
from sqlalchemy.orm import Mapped, mapped_column

from common.models import UUIDPrimaryKeyMixin, _now_utc
from database import Base


class OtpVerification(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "otp_verifications"

    phone_number: Mapped[str] = mapped_column(Text, nullable=False)
    otp_hash: Mapped[str] = mapped_column(Text, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(TIMESTAMPTZ, nullable=False)
    used_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMPTZ, nullable=False, default=_now_utc
    )

    __table_args__ = (
        Index("ix_otp_verifications_phone_number", "phone_number"),
    )


class RefreshToken(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "refresh_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    token_hash: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    issued_at: Mapped[datetime] = mapped_column(
        TIMESTAMPTZ, nullable=False, default=_now_utc
    )
    expires_at: Mapped[datetime] = mapped_column(TIMESTAMPTZ, nullable=False)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)
