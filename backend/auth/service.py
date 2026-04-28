"""
Auth service — all business logic for OTP, JWT, and token management.

Rules:
- Every function is async and accepts an explicit db: AsyncSession parameter.
- No FastAPI concerns (Request, Response) enter this layer.
- Domain errors are raised as AppError subclasses.
"""

import hashlib
import random
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth.models import OtpVerification, RefreshToken
from common.exceptions import ConflictError, TooManyRequestsError, UnauthorizedError
from config import get_settings
from users.models import User

OTP_MAX_ATTEMPTS = 5
OTP_RESEND_COOLDOWN_SECONDS = 60

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


# ── Internal helpers ──────────────────────────────────────────


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _hash_refresh_token(token: str) -> str:
    """SHA-256 hash of a refresh token string."""
    return hashlib.sha256(token.encode()).hexdigest()


def _make_refresh_token() -> tuple[str, str]:
    """Return (plain_token, hashed_token). Plain is sent to the client; hash is stored."""
    plain = secrets.token_urlsafe(48)
    return plain, _hash_refresh_token(plain)


def _create_access_token(user_id: str) -> str:
    settings = get_settings()
    now = _now()
    payload = {
        "sub": user_id,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=settings.jwt_access_token_expire_minutes)).timestamp()),
        "type": "access",
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


async def _get_or_create_user(db: AsyncSession, phone_number: str) -> User:
    result = await db.execute(select(User).where(User.phone_number == phone_number))
    user = result.scalar_one_or_none()
    if user is None:
        user = User(phone_number=phone_number, is_verified=True)
        db.add(user)
        await db.flush()
    elif not user.is_verified:
        user.is_verified = True
        await db.flush()
    return user


async def _store_refresh_token(
    db: AsyncSession, user_id: uuid.UUID, token_hash: str
) -> None:
    settings = get_settings()
    rt = RefreshToken(
        user_id=user_id,
        token_hash=token_hash,
        issued_at=_now(),
        expires_at=_now() + timedelta(days=settings.jwt_refresh_token_expire_days),
    )
    db.add(rt)
    await db.flush()


# ── Public service functions ──────────────────────────────────


async def request_otp(db: AsyncSession, phone_number: str) -> str | None:
    """
    Generate and store an OTP for the given phone number.

    Returns:
        The plain OTP in mock mode (so callers can surface it in dev).
        None in production mode (OTP should be sent via SMS instead).
    """
    settings = get_settings()
    now = _now()

    # Abuse guard: block if an unused, non-expired OTP was created within the cooldown window
    recent = await db.execute(
        select(OtpVerification)
        .where(
            OtpVerification.phone_number == phone_number,
            OtpVerification.used_at.is_(None),
            OtpVerification.expires_at > now,
            OtpVerification.created_at > now - timedelta(seconds=OTP_RESEND_COOLDOWN_SECONDS),
        )
        .limit(1)
    )
    if recent.scalar_one_or_none():
        raise TooManyRequestsError("Please wait before requesting another OTP")

    if settings.otp_mock_mode:
        otp = "123456"
    else:
        otp = f"{random.randint(0, 999_999):06d}"

    otp_hash = pwd_context.hash(otp)
    record = OtpVerification(
        phone_number=phone_number,
        otp_hash=otp_hash,
        expires_at=_now() + timedelta(minutes=settings.otp_ttl_minutes),
        attempt_count=0,
    )
    db.add(record)
    await db.flush()

    return otp if settings.otp_mock_mode else None


async def verify_otp(
    db: AsyncSession, phone_number: str, otp: str
) -> tuple[str, str]:
    """
    Validate OTP. Create user on first login. Return (access_token, refresh_token).

    Raises:
        UnauthorizedError: if OTP is invalid, expired, or already used.
    """
    settings = get_settings()
    now = _now()

    result = await db.execute(
        select(OtpVerification)
        .where(
            OtpVerification.phone_number == phone_number,
            OtpVerification.used_at.is_(None),
            OtpVerification.expires_at > now,
        )
        .order_by(OtpVerification.created_at.desc())
        .limit(1)
    )
    record = result.scalar_one_or_none()

    if record is None:
        raise UnauthorizedError("OTP not found, expired, or already used")

    # Brute-force guard: already maxed out
    if record.attempt_count >= OTP_MAX_ATTEMPTS:
        record.used_at = now
        await db.flush()
        raise TooManyRequestsError("Too many attempts. Request a new OTP.")

    # Validate
    if settings.otp_mock_mode:
        valid = otp == "123456"
    else:
        valid = pwd_context.verify(otp, record.otp_hash)

    if not valid:
        record.attempt_count += 1
        # Do NOT mark used_at here — keep the record findable so the next
        # request hits the brute-force guard (attempt_count >= OTP_MAX_ATTEMPTS)
        # and returns 429 instead of a confusing 401.
        await db.flush()
        raise UnauthorizedError("Invalid OTP")

    # Mark as used
    record.used_at = now
    await db.flush()

    # Create or fetch user
    user = await _get_or_create_user(db, phone_number)

    # Issue tokens
    access_token = _create_access_token(str(user.id))
    refresh_plain, refresh_hash = _make_refresh_token()
    await _store_refresh_token(db, user.id, refresh_hash)

    return access_token, refresh_plain


async def refresh_access_token(
    db: AsyncSession, refresh_token_str: str
) -> tuple[str, str]:
    """
    Rotate a refresh token. Revoke the old one and issue a new pair.

    Raises:
        UnauthorizedError: if the token is invalid, revoked, or expired.
    """
    now = _now()
    token_hash = _hash_refresh_token(refresh_token_str)

    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked_at.is_(None),
            RefreshToken.expires_at > now,
        )
    )
    record = result.scalar_one_or_none()

    if record is None:
        raise UnauthorizedError("Invalid, revoked, or expired refresh token")

    # Revoke old token
    record.revoked_at = now
    await db.flush()

    # Issue new pair
    access_token = _create_access_token(str(record.user_id))
    refresh_plain, refresh_hash = _make_refresh_token()
    await _store_refresh_token(db, record.user_id, refresh_hash)

    return access_token, refresh_plain


async def logout(db: AsyncSession, refresh_token_str: str) -> None:
    """
    Revoke a specific refresh token.

    Raises:
        UnauthorizedError: if the token does not exist or is already revoked.
    """
    token_hash = _hash_refresh_token(refresh_token_str)

    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked_at.is_(None),
        )
    )
    record = result.scalar_one_or_none()

    if record is None:
        raise UnauthorizedError("Refresh token not found or already revoked")

    record.revoked_at = _now()
    await db.flush()


async def decode_access_token(token: str) -> str:
    """
    Decode and validate a JWT access token.

    Returns:
        user_id (str) extracted from the 'sub' claim.

    Raises:
        UnauthorizedError: on any validation failure.
    """
    settings = get_settings()
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
        )
    except JWTError:
        raise UnauthorizedError("Invalid or expired access token")

    user_id: str | None = payload.get("sub")
    token_type: str | None = payload.get("type")

    if not user_id or token_type != "access":
        raise UnauthorizedError("Invalid token payload")

    return user_id
