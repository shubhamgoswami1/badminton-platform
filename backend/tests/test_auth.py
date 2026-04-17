"""
P1 Auth tests — 10 required cases.

All tests run in mock OTP mode (OTP_MOCK_MODE=true, the default in .env.example),
so no SMS provider is needed and the OTP is always "123456".

Test isolation: each test gets its own DB session that is rolled back on teardown.
"""

from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth.models import OtpVerification, RefreshToken
from auth.service import _hash_refresh_token, _make_refresh_token, _store_refresh_token
from users.models import User

PHONE = "+919876543210"
PHONE_2 = "+919876543211"


# ── Helpers ───────────────────────────────────────────────────


async def _do_full_login(client: AsyncClient, phone: str = PHONE) -> dict:
    """Request OTP then verify it. Returns the token pair dict."""
    await client.post("/api/v1/auth/otp/request", json={"phone_number": phone})
    resp = await client.post(
        "/api/v1/auth/otp/verify",
        json={"phone_number": phone, "otp": "123456"},
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["data"]


# ── Test cases ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_request_otp_returns_200_and_creates_db_record(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """POST /auth/otp/request → 200, OTP record in DB."""
    resp = await client.post("/api/v1/auth/otp/request", json={"phone_number": PHONE})

    assert resp.status_code == 200
    body = resp.json()
    assert body["error"] is None
    assert body["data"]["message"] is not None
    # Mock mode exposes the OTP in the response
    assert body["data"]["otp"] == "123456"

    # Verify DB record was created
    result = await db_session.execute(
        select(OtpVerification).where(OtpVerification.phone_number == PHONE)
    )
    record = result.scalar_one_or_none()
    assert record is not None
    assert record.used_at is None


@pytest.mark.asyncio
async def test_verify_otp_correct_returns_token_pair(client: AsyncClient) -> None:
    """POST /auth/otp/verify with correct OTP → access_token + refresh_token."""
    await client.post("/api/v1/auth/otp/request", json={"phone_number": PHONE})
    resp = await client.post(
        "/api/v1/auth/otp/verify",
        json={"phone_number": PHONE, "otp": "123456"},
    )

    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["access_token"]
    assert data["refresh_token"]
    assert data["token_type"] == "bearer"


@pytest.mark.asyncio
async def test_verify_otp_wrong_otp_returns_401(client: AsyncClient) -> None:
    """POST /auth/otp/verify with wrong OTP → 401."""
    await client.post("/api/v1/auth/otp/request", json={"phone_number": PHONE})
    resp = await client.post(
        "/api/v1/auth/otp/verify",
        json={"phone_number": PHONE, "otp": "000000"},
    )

    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHORIZED"


@pytest.mark.asyncio
async def test_verify_otp_expired_returns_401(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """POST /auth/otp/verify against an expired OTP → 401."""
    # Create an OTP record that is already expired
    from passlib.context import CryptContext

    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    record = OtpVerification(
        phone_number=PHONE,
        otp_hash=pwd_context.hash("123456"),
        expires_at=datetime.now(timezone.utc) - timedelta(minutes=1),  # already expired
    )
    db_session.add(record)
    await db_session.flush()

    resp = await client.post(
        "/api/v1/auth/otp/verify",
        json={"phone_number": PHONE, "otp": "123456"},
    )

    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_verify_otp_used_returns_401(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """POST /auth/otp/verify against an already-used OTP → 401."""
    from passlib.context import CryptContext

    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    record = OtpVerification(
        phone_number=PHONE,
        otp_hash=pwd_context.hash("123456"),
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        used_at=datetime.now(timezone.utc),  # already used
    )
    db_session.add(record)
    await db_session.flush()

    resp = await client.post(
        "/api/v1/auth/otp/verify",
        json={"phone_number": PHONE, "otp": "123456"},
    )

    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_refresh_token_returns_new_pair_and_revokes_old(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """POST /auth/token/refresh with valid token → new pair, old token revoked."""
    tokens = await _do_full_login(client, PHONE)
    old_refresh = tokens["refresh_token"]

    resp = await client.post(
        "/api/v1/auth/token/refresh", json={"refresh_token": old_refresh}
    )

    assert resp.status_code == 200
    new_tokens = resp.json()["data"]
    assert new_tokens["access_token"]
    assert new_tokens["refresh_token"]
    assert new_tokens["refresh_token"] != old_refresh

    # Old token must now be revoked in DB
    result = await db_session.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == _hash_refresh_token(old_refresh)
        )
    )
    old_record = result.scalar_one_or_none()
    assert old_record is not None
    assert old_record.revoked_at is not None


@pytest.mark.asyncio
async def test_refresh_token_revoked_returns_401(client: AsyncClient) -> None:
    """POST /auth/token/refresh with a revoked token → 401."""
    tokens = await _do_full_login(client, PHONE)
    old_refresh = tokens["refresh_token"]

    # Use the token once (rotates it, old is now revoked)
    await client.post("/api/v1/auth/token/refresh", json={"refresh_token": old_refresh})

    # Try to use the old (now revoked) token again
    resp = await client.post(
        "/api/v1/auth/token/refresh", json={"refresh_token": old_refresh}
    )

    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_logout_revokes_refresh_token(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """POST /auth/logout → refresh token is revoked in DB."""
    tokens = await _do_full_login(client, PHONE)
    access = tokens["access_token"]
    refresh = tokens["refresh_token"]

    resp = await client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": refresh},
        headers={"Authorization": f"Bearer {access}"},
    )

    assert resp.status_code == 200

    result = await db_session.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == _hash_refresh_token(refresh)
        )
    )
    record = result.scalar_one_or_none()
    assert record is not None
    assert record.revoked_at is not None


@pytest.mark.asyncio
async def test_health_with_valid_token_returns_200(client: AsyncClient) -> None:
    """GET /api/v1/health with valid Bearer token → 200, get_current_user resolves."""
    tokens = await _do_full_login(client, PHONE)
    access = tokens["access_token"]

    resp = await client.get(
        "/api/v1/health",
        headers={"Authorization": f"Bearer {access}"},
    )

    assert resp.status_code == 200
    assert resp.json()["data"]["status"] == "ok"


@pytest.mark.asyncio
async def test_health_without_token_returns_401(client: AsyncClient) -> None:
    """GET /api/v1/health with no token → 401."""
    resp = await client.get("/api/v1/health")

    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHORIZED"
