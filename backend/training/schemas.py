import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator

from common.enums import GoalStatus, SessionType


class TrainingLogCreate(BaseModel):
    session_type: SessionType
    duration_minutes: int
    notes: Optional[str] = None
    logged_at: Optional[datetime] = None

    @field_validator("duration_minutes")
    @classmethod
    def positive_duration(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("duration_minutes must be positive")
        return v


class TrainingLogUpdate(BaseModel):
    session_type: Optional[SessionType] = None
    duration_minutes: Optional[int] = None
    notes: Optional[str] = None
    logged_at: Optional[datetime] = None


class TrainingLogResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    session_type: str
    duration_minutes: int
    notes: Optional[str] = None
    logged_at: datetime
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class TrainingGoalCreate(BaseModel):
    title: str
    description: Optional[str] = None
    target_date: Optional[datetime] = None


class TrainingGoalUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    target_date: Optional[datetime] = None
    status: Optional[GoalStatus] = None


class TrainingGoalResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    title: str
    description: Optional[str] = None
    target_date: Optional[datetime] = None
    status: str
    completed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
