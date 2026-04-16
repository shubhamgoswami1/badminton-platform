"""
Dev seed script — populates a fresh local database with enough data to develop against.

Usage:
    python scripts/seed_dev.py

Assumptions:
- DATABASE_URL is set (via .env or environment)
- All Alembic migrations have been run: `alembic upgrade head`
- OTP_MOCK_MODE=true so no SMS is sent

This script will be filled out in P1+ as models are created.
Currently it just verifies the DB connection and exits cleanly.
"""

import asyncio
import sys
from pathlib import Path

# Allow running from the backend/ root
sys.path.insert(0, str(Path(__file__).parent.parent))

import structlog
from sqlalchemy import text

from database import AsyncSessionLocal
from logging_config import configure_logging

configure_logging()
log = structlog.get_logger()


async def seed() -> None:
    log.info("seed_start", note="No data to seed yet — stub placeholder")
    async with AsyncSessionLocal() as db:
        result = await db.execute(text("SELECT 1"))
        row = result.scalar()
        assert row == 1, "DB connectivity check failed"
    log.info("seed_complete", status="ok")


if __name__ == "__main__":
    asyncio.run(seed())
