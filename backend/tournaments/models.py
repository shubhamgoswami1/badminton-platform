"""
Tournament domain models — all phases in one file.

P3: Tournament
P4: TournamentParticipant
P5: Match
P6: MatchScore
"""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, ForeignKey, Integer, Numeric, Text
from sqlalchemy.dialects.postgresql import TIMESTAMPTZ, UUID
from sqlalchemy.orm import Mapped, mapped_column

from common.models import UUIDPrimaryKeyMixin, _now_utc
from database import Base


class Tournament(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "tournaments"

    organiser_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    city: Mapped[Optional[str]] = mapped_column(Text, nullable=True, index=True)
    venue_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("venues.id"), nullable=True
    )
    format: Mapped[str] = mapped_column(Text, nullable=False)
    match_format: Mapped[str] = mapped_column(Text, nullable=False)
    play_type: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="DRAFT", index=True)
    max_participants: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    registration_deadline: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)
    starts_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)
    bracket_generated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(TIMESTAMPTZ, nullable=False, default=_now_utc)
    updated_at: Mapped[datetime] = mapped_column(TIMESTAMPTZ, nullable=False, default=_now_utc, onupdate=_now_utc)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)


class TournamentParticipant(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "tournament_participants"

    tournament_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tournaments.id"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    partner_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True
    )
    seed_order: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    registered_at: Mapped[datetime] = mapped_column(TIMESTAMPTZ, nullable=False, default=_now_utc)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="REGISTERED")

    __table_args__ = (
        __import__("sqlalchemy").UniqueConstraint("tournament_id", "user_id"),
    )


class Match(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "matches"

    tournament_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tournaments.id"), nullable=False, index=True
    )
    round: Mapped[int] = mapped_column(Integer, nullable=False)
    match_number: Mapped[int] = mapped_column(Integer, nullable=False)
    side_a_participant_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tournament_participants.id"), nullable=True
    )
    side_b_participant_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tournament_participants.id"), nullable=True
    )
    winner_participant_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tournament_participants.id"), nullable=True
    )
    status: Mapped[str] = mapped_column(Text, nullable=False, default="PENDING")
    scheduled_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)
    completed_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMPTZ, nullable=True)
    next_match_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("matches.id"), nullable=True
    )
    winner_feeds_side: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # 'A' or 'B'
    created_at: Mapped[datetime] = mapped_column(TIMESTAMPTZ, nullable=False, default=_now_utc)


class MatchScore(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "match_scores"

    match_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("matches.id"), nullable=False, index=True
    )
    set_number: Mapped[int] = mapped_column(Integer, nullable=False)
    side_a_score: Mapped[int] = mapped_column(Integer, nullable=False)
    side_b_score: Mapped[int] = mapped_column(Integer, nullable=False)
    submitted_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    submitted_at: Mapped[datetime] = mapped_column(TIMESTAMPTZ, nullable=False, default=_now_utc)
