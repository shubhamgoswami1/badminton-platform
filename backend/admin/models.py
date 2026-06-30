import uuid
from datetime import datetime
from typing import Optional

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from common.models import UUIDPrimaryKeyMixin, _now_utc
from database import Base


class AdminLog(UUIDPrimaryKeyMixin, Base):
    """Immutable audit record written for every admin action."""

    __tablename__ = "admin_logs"

    admin_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        sa.ForeignKey("users.id"),
        nullable=False,
        index=True,
    )
    action: Mapped[str] = mapped_column(sa.Text, nullable=False, index=True)
    target_type: Mapped[str] = mapped_column(sa.Text, nullable=False)
    target_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        sa.TIMESTAMP(timezone=True), nullable=False, default=_now_utc
    )
