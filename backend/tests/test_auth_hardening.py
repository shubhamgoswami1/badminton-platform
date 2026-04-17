"""
P12 Auth hardening tests — 3 required cases.

Tests OTP brute-force protection and resend rate limiting.
Uses OTP mock mode where "123456" is always the valid code.
"""

import asyncio

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

PHONE = "+919000000001"
PHONE_2 = "+919000000002"


@pytest.mark.asyncio
async def test_otp_brute_force_lockout(client: AsyncClient, db_session: AsyncSession):
    """5 failed OTP attempts → 6th returns 429 and OTP is invalidated."""
    await client.post("/api/v1/auth/otp/request", json={"phone_number": PHONE})

    # 5 failed attempts with wrong OTP
    for _ in range(5):
        r = await client.post(
            "/api/v1/auth/otp/verify",
            json={"phone_number": PHONE, "otp": "000000"},
        )
        assert r.status_code in (401, 429)

    # 6th attempt (even with correct OTP) should be locked out
    r = await client.post(
        "/api/v1/auth/otp/verify",
        json={"phone_number": PHONE, "otp": "123456"},
    )
    assert r.status_code == 429


@pytest.mark.asyncio
async def test_otp_resend_cooldown(client: AsyncClient, db_session: AsyncSession):
    """Requesting OTP twice within 60s → second request returns 429."""
    r1 = await client.post("/api/v1/auth/otp/request", json={"phone_number": PHONE_2})
    assert r1.status_code == 200

    r2 = await client.post("/api/v1/auth/otp/request", json={"phone_number": PHONE_2})
    assert r2.status_code == 429


@pytest.mark.asyncio
async def test_otp_resend_allowed_after_use(client: AsyncClient, db_session: AsyncSession):
    """After successfully using an OTP, a new one can be requested immediately."""
    phone = "+919000000003"

    # Request + verify
    await client.post("/api/v1/auth/otp/request", json={"phone_number": phone})
    r = await client.post("/api/v1/auth/otp/verify", json={"phone_number": phone, "otp": "123456"})
    assert r.status_code == 200

    # Now request again — previous OTP is used, so no cooldown blocker on the new request
    r2 = await client.post("/api/v1/auth/otp/request", json={"phone_number": phone})
    assert r2.status_code == 200
