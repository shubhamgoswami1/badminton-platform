import re

from pydantic import BaseModel, field_validator


def _validate_phone(v: str) -> str:
    v = v.strip()
    if not re.match(r"^\+?[0-9]{7,15}$", v):
        raise ValueError("Invalid phone number — use 7-15 digits, optional leading +")
    return v


# ── Requests ─────────────────────────────────────────────────


class OtpRequestBody(BaseModel):
    phone_number: str

    @field_validator("phone_number")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        return _validate_phone(v)


class OtpVerifyBody(BaseModel):
    phone_number: str
    otp: str

    @field_validator("phone_number")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        return _validate_phone(v)

    @field_validator("otp")
    @classmethod
    def validate_otp(cls, v: str) -> str:
        v = v.strip()
        if not re.match(r"^[0-9]{6}$", v):
            raise ValueError("OTP must be a 6-digit number")
        return v


class TokenRefreshBody(BaseModel):
    refresh_token: str


class LogoutBody(BaseModel):
    refresh_token: str


# ── Responses ────────────────────────────────────────────────


class OtpRequestResponse(BaseModel):
    message: str
    # Only populated in mock/dev mode so developers can see the OTP without SMS
    otp: str | None = None


class TokenPairResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
