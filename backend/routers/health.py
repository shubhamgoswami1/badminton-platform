from fastapi import APIRouter
from fastapi.responses import JSONResponse

from common.response import ok

router = APIRouter(tags=["health"])


@router.get("/health", response_class=JSONResponse, status_code=200)
async def get_health() -> dict:
    return ok({"status": "ok"})
