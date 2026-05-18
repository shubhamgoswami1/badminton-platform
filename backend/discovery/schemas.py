import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class VenueCreate(BaseModel):
    name: str
    city: Optional[str] = None
    address: Optional[str] = None
    court_count: Optional[int] = None


class VenueResponse(BaseModel):
    id: uuid.UUID
    name: str
    city: Optional[str] = None
    address: Optional[str] = None
    court_count: Optional[int] = None
    submitted_by: Optional[uuid.UUID] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class PlayerDiscoveryResponse(BaseModel):
    user_id: uuid.UUID
    display_name: str
    city: Optional[str] = None
    skill_level: Optional[str] = None
    play_style: Optional[str] = None
    bio: Optional[str] = None
    elo_rating: Optional[float] = None
    matches_played: int = 0
    wins: int = 0
    losses: int = 0
    reliability_score: float = 5.0
    distance_km: Optional[float] = None

    model_config = {"from_attributes": True}


class TournamentDiscoveryResponse(BaseModel):
    id: uuid.UUID
    title: str
    city: Optional[str] = None
    format: str
    play_type: str
    status: str
    starts_at: Optional[datetime] = None
    max_participants: Optional[int] = None

    model_config = {"from_attributes": True}
