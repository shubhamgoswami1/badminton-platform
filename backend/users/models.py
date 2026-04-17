import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, Text
from sqlalchemy.dialects.postgresql import TIMESTAMPTZ, UUID
from sqlalchemy.orm import Mapped, mapped_column

from common.models import TimestampMixin, UUIDPrimaryKeyMixin
from database import Base


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "users"

    phone_number: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    is_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)
