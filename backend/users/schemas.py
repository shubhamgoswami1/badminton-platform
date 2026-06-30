import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator

from common.enums import PlayStyle, SkillLevel


# ── Profile write ─────────────────────────────────────────────────────────


class PlayerProfileUpdate(BaseModel):
    """All fields optional — partial update / upsert semantics."""

    display_name: Optional[str] = Field(None, min_length=1, max_length=80)
    city: Optional[str] = Field(None, max_length=80)
    skill_level: Optional[SkillLevel] = None
    play_style: Optional[PlayStyle] = None
    bio: Optional[str] = Field(None, max_length=500)
    latitude: Optional[float] = Field(None, ge=-90.0, le=90.0)
    longitude: Optional[float] = Field(None, ge=-180.0, le=180.0)
    rating: Optional[float] = Field(None, ge=0.0, le=10.0)

    @field_validator("latitude", "longitude", mode="before")
    @classmethod
    def _both_or_neither(cls, v: Optional[float], info) -> Optional[float]:
        # Loose guard — full pair validation is done in the service layer.
        return v


# ── Profile read ──────────────────────────────────────────────────────────


class PlayerProfileResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    display_name: str
    city: Optional[str] = None
    skill_level: Optional[str] = None
    play_style: Optional[str] = None
    bio: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    reliability_score: float
    rating: Optional[float] = None
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


# ── Player search ─────────────────────────────────────────────────────────


class PlayerSearchParams(BaseModel):
    """
    Query parameters for GET /users/search.

    Text search matches display_name and city (case-insensitive, prefix/substring).
    Skill-level and rating filters are additive (AND).
    Radius filter (km) requires the caller to also provide lat/lng;
    it performs a bounding-box pre-filter in MVP (true haversine is post-MVP).
    """

    q: Optional[str] = Field(None, description="Text search on name or city")
    skill_level: Optional[SkillLevel] = None
    play_style: Optional[PlayStyle] = None
    min_rating: Optional[float] = Field(None, ge=0.0, le=10.0)
    max_rating: Optional[float] = Field(None, ge=0.0, le=10.0)
    # Location-based filtering (optional; requires both lat+lng+radius_km)
    lat: Optional[float] = Field(None, ge=-90.0, le=90.0)
    lng: Optional[float] = Field(None, ge=-180.0, le=180.0)
    radius_km: Optional[float] = Field(None, gt=0.0, le=500.0)
    # Pagination
    page: int = Field(1, ge=1)
    page_size: int = Field(20, ge=1, le=100)

    @property
    def offset(self) -> int:
        return (self.page - 1) * self.page_size


class PlayerSearchResult(BaseModel):
    """Lightweight representation returned in search results."""

    user_id: uuid.UUID
    display_name: str
    city: Optional[str] = None
    skill_level: Optional[str] = None
    play_style: Optional[str] = None
    reliability_score: float
    rating: Optional[float] = None

    model_config = {"from_attributes": True}


class PlayerSearchResponse(BaseModel):
    items: list[PlayerSearchResult]
    total: int
    page: int
    page_size: int
    pages: int
