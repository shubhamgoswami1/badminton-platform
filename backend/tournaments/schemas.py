import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator

from common.enums import (
    MatchFormat,
    MatchStatus,
    ParticipantStatus,
    PlayType,
    TournamentFormat,
    TournamentStatus,
)


# ── Tournament ────────────────────────────────────────────────

class TournamentCreate(BaseModel):
    title: str
    description: Optional[str] = None
    city: Optional[str] = None
    # Optional GPS pin for the tournament venue (enables /nearby discovery)
    latitude: Optional[float] = Field(None, ge=-90.0, le=90.0)
    longitude: Optional[float] = Field(None, ge=-180.0, le=180.0)
    format: TournamentFormat
    match_format: MatchFormat
    play_type: PlayType
    max_participants: Optional[int] = Field(None, ge=2, le=1024)
    registration_deadline: Optional[datetime] = None
    starts_at: Optional[datetime] = None


class TournamentUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    city: Optional[str] = None
    match_format: Optional[MatchFormat] = None
    play_type: Optional[PlayType] = None
    max_participants: Optional[int] = None
    registration_deadline: Optional[datetime] = None
    starts_at: Optional[datetime] = None


class TournamentStatusTransitionRequest(BaseModel):
    next_status: TournamentStatus


class TournamentResponse(BaseModel):
    id: uuid.UUID
    organiser_id: uuid.UUID
    title: str
    description: Optional[str] = None
    city: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    format: str
    match_format: str
    play_type: str
    status: str
    max_participants: Optional[int] = None
    participant_count: Optional[int] = None  # populated by service where cheap
    registration_deadline: Optional[datetime] = None
    starts_at: Optional[datetime] = None
    bracket_generated: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class TournamentNearbyResult(TournamentResponse):
    """TournamentResponse with an additional haversine distance field."""

    distance_km: Optional[float] = None


# ── Participants ──────────────────────────────────────────────

class ParticipantRegisterRequest(BaseModel):
    partner_user_id: Optional[uuid.UUID] = None


class SeedOrderRequest(BaseModel):
    ordered_participant_ids: list[uuid.UUID]


class ParticipantResponse(BaseModel):
    id: uuid.UUID
    tournament_id: uuid.UUID
    user_id: uuid.UUID
    partner_user_id: Optional[uuid.UUID] = None
    seed_order: Optional[int] = None
    registered_at: datetime
    status: str

    model_config = {"from_attributes": True}


# ── Matches ───────────────────────────────────────────────────

class MatchResponse(BaseModel):
    id: uuid.UUID
    tournament_id: uuid.UUID
    round: int
    match_number: int
    side_a_participant_id: Optional[uuid.UUID] = None
    side_b_participant_id: Optional[uuid.UUID] = None
    winner_participant_id: Optional[uuid.UUID] = None
    status: str
    next_match_id: Optional[uuid.UUID] = None
    winner_feeds_side: Optional[str] = None
    scheduled_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class StandingEntry(BaseModel):
    participant_id: uuid.UUID
    user_id: uuid.UUID
    matches_played: int
    wins: int
    losses: int
    points: int
