from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

import auth.service as auth_service
from auth.schemas import (
    LogoutBody,
    OtpRequestBody,
    OtpRequestResponse,
    OtpVerifyBody,
    TokenPairResponse,
    TokenRefreshBody,
)
from common.dependencies import get_current_user
from common.response import ok
from database import get_db
from users.models import User

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/otp/request",
    status_code=status.HTTP_200_OK,
)
async def request_otp(
    body: OtpRequestBody,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Request a one-time password for the given phone number.
    In mock mode (OTP_MOCK_MODE=true) the OTP is always 123456 and is returned
    in the response so developers can test without an SMS provider.
    """
    otp = await auth_service.request_otp(db, body.phone_number)
    payload = OtpRequestResponse(
        message="OTP sent" if otp is None else "OTP generated (mock mode)",
        otp=otp,
    )
    return ok(payload.model_dump())


@router.post(
    "/otp/verify",
    status_code=status.HTTP_200_OK,
)
async def verify_otp(
    body: OtpVerifyBody,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Verify the OTP and receive an access + refresh token pair.
    Creates a new user account on first successful verification.
    """
    access_token, refresh_token = await auth_service.verify_otp(
        db, body.phone_number, body.otp
    )
    payload = TokenPairResponse(access_token=access_token, refresh_token=refresh_token)
    return ok(payload.model_dump())


@router.post(
    "/token/refresh",
    status_code=status.HTTP_200_OK,
)
async def refresh_token(
    body: TokenRefreshBody,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Rotate a refresh token. The old token is revoked and a new pair is issued.
    """
    access_token, new_refresh = await auth_service.refresh_access_token(
        db, body.refresh_token
    )
    payload = TokenPairResponse(access_token=access_token, refresh_token=new_refresh)
    return ok(payload.model_dump())


@router.post(
    "/logout",
    status_code=status.HTTP_200_OK,
)
async def logout(
    body: LogoutBody,
    db: Annotated[AsyncSession, Depends(get_db)],
    _current_user: Annotated[User, Depends(get_current_user)],
) -> dict:
    """
    Revoke the supplied refresh token. Requires a valid Bearer access token.
    """
    await auth_service.logout(db, body.refresh_token)
    return ok({"message": "Logged out successfully"})
