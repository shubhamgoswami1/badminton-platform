import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


# ── Action constants ──────────────────────────────────────────────────────────

class AdminAction:
    BAN_USER = "BAN_USER"
    UNBAN_USER = "UNBAN_USER"
    DELETE_TOURNAMENT = "DELETE_TOURNAMENT"


class AdminTargetType:
    USER = "USER"
    TOURNAMENT = "TOURNAMENT"


# ── Request schemas ───────────────────────────────────────────────────────────

class BanUserRequest(BaseModel):
    user_id: uuid.UUID
    notes: Optional[str] = None


class UnbanUserRequest(BaseModel):
    user_id: uuid.UUID
    notes: Optional[str] = None


class DeleteTournamentRequest(BaseModel):
    tournament_id: uuid.UUID
    notes: Optional[str] = None


# ── Response schemas ──────────────────────────────────────────────────────────

class AdminLogResponse(BaseModel):
    id: uuid.UUID
    admin_id: uuid.UUID
    action: str
    target_type: str
    target_id: uuid.UUID
    notes: Optional[str]
    created_at: datetime

    model_config = {"from_attributes": True}
