"""
Pydantic schemas for the scores / match-detail API.
"""

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator


# ── Input schemas ──────────────────────────────────────────────────────────────

class SetScoreInput(BaseModel):
    set_number: int
    side_a_score: int
    side_b_score: int


class SubmitScoreRequest(BaseModel):
    """
    Submit all set scores and declare a winner in one shot.
    Transitions match: PENDING / IN_PROGRESS → COMPLETED.
    Applies Elo to both players (singles only).
    """

    sets: list[SetScoreInput]
    winner_participant_id: uuid.UUID

    @field_validator("sets")
    @classmethod
    def at_least_one_set(cls, v: list) -> list:
        if not v:
            raise ValueError("At least one set score is required")
        return v


class UpdateScoreRequest(BaseModel):
    """
    Save intermediate set scores without completing the match.
    Transitions match: PENDING → IN_PROGRESS (if not already).
    """

    sets: list[SetScoreInput]

    @field_validator("sets")
    @classmethod
    def at_least_one_set(cls, v: list) -> list:
        if not v:
            raise ValueError("At least one set score is required")
        return v


class CompleteMatchRequest(BaseModel):
    """
    Finalise a match that already has scores recorded (IN_PROGRESS).
    Alternatively accepts fresh sets to replace existing scores.
    Transitions match: PENDING / IN_PROGRESS → COMPLETED.
    Applies Elo to both players (singles only).
    """

    winner_participant_id: uuid.UUID
    # Optional — if supplied, replaces all existing score rows before completing.
    sets: Optional[list[SetScoreInput]] = None


# ── Output schemas ─────────────────────────────────────────────────────────────

class SetScoreResponse(BaseModel):
    id: uuid.UUID
    match_id: uuid.UUID
    set_number: int
    side_a_score: int
    side_b_score: int
    submitted_by: Optional[uuid.UUID] = None
    submitted_at: datetime

    model_config = {"from_attributes": True}


class MatchScoreResponse(BaseModel):
    """Returned by submit-score and get-score (legacy shape, kept for compatibility)."""

    match_id: uuid.UUID
    status: str
    winner_participant_id: Optional[uuid.UUID] = None
    sets: list[SetScoreResponse]


class MatchDetailResponse(BaseModel):
    """
    Full match detail including metadata, current scores and Elo state.
    Returned by GET /matches/{id} and all mutating endpoints.
    """

    match_id: uuid.UUID
    tournament_id: uuid.UUID
    round: int
    match_number: int
    side_a_participant_id: Optional[uuid.UUID] = None
    side_b_participant_id: Optional[uuid.UUID] = None
    winner_participant_id: Optional[uuid.UUID] = None
    status: str
    elo_applied: bool
    version: int
    scheduled_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    sets: list[SetScoreResponse]


class MyMatchItem(BaseModel):
    """
    A match the current user is participating in, with tournament context.
    Returned by GET /matches/my.
    """

    # Match fields
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
    elo_applied: bool
    version: int
    # Tournament context (mirrors Flutter MatchWithContext)
    tournament_title: str
    organiser_id: uuid.UUID
