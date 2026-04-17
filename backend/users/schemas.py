import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel

from common.enums import SkillLevel, PlayStyle


class PlayerProfileUpdate(BaseModel):
    display_name: Optional[str] = None
    city: Optional[str] = None
    skill_level: Optional[SkillLevel] = None
    play_style: Optional[PlayStyle] = None
    bio: Optional[str] = None


class PlayerProfileResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    display_name: str
    city: Optional[str] = None
    skill_level: Optional[str] = None
    play_style: Optional[str] = None
    bio: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class UserResponse(BaseModel):
    id: uuid.UUID
    phone_number: str
    is_verified: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class UserWithProfileResponse(BaseModel):
    user: UserResponse
    profile: Optional[PlayerProfileResponse] = None
