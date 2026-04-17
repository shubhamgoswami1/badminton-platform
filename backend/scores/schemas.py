import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator


class SetScoreInput(BaseModel):
    set_number: int
    side_a_score: int
    side_b_score: int


class SubmitScoreRequest(BaseModel):
    sets: list[SetScoreInput]
    winner_participant_id: uuid.UUID

    @field_validator("sets")
    @classmethod
    def at_least_one_set(cls, v: list) -> list:
        if not v:
            raise ValueError("At least one set score is required")
        return v


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
    match_id: uuid.UUID
    status: str
    winner_participant_id: Optional[uuid.UUID] = None
    sets: list[SetScoreResponse]
