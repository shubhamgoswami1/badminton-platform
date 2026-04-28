"""
Shared pytest fixtures for all backend tests.

Assumptions:
- Tests run against a real PostgreSQL instance (not mocked).
- The test DB URL is provided via TEST_DATABASE_URL env var; falls back to the
  default DATABASE_URL with the database name suffixed by "_test".
- The engine is created inside a session-scoped async fixture so that asyncpg
  connections are always bound to the single session event loop.
  (Module-level engine creation caused "Future attached to a different loop"
  errors because asyncpg bound connections to the import-time loop.)
- Each test function gets a clean DB session that is rolled back after the test,
  providing isolation without needing to truncate tables between tests.

Usage:
    pytest tests/
"""

import os
from typing import AsyncGenerator

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from config import get_settings
from database import Base, get_db
from main import app

# Import all models so Base.metadata knows about them
from auth.models import OtpVerification, RefreshToken  # noqa: F401
from users.models import PlayerProfile, User  # noqa: F401
from tournaments.models import Match, MatchScore, Tournament, TournamentParticipant  # noqa: F401
from training.models import TrainingGoal, TrainingLog  # noqa: F401
from discovery.models import Venue  # noqa: F401

settings = get_settings()

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    settings.database_url.replace("/badminton", "/badminton_test"),
)


# ---------------------------------------------------------------------------
# Session-scoped engine — created inside the session event loop so that all
# asyncpg connections are bound to the same loop as the test coroutines.
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture(scope="session")
async def _engine():
    """Create the async engine, build all tables, yield, then tear down."""
    engine = create_async_engine(TEST_DATABASE_URL, echo=False, pool_pre_ping=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture(scope="session")
async def _session_factory(_engine):
    """Session-scoped factory bound to the shared test engine."""
    yield async_sessionmaker(
        bind=_engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autoflush=False,
        autocommit=False,
    )


# ---------------------------------------------------------------------------
# Per-test DB session with rollback isolation
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def db_session(_session_factory) -> AsyncGenerator[AsyncSession, None]:
    async with _session_factory() as session:
        yield session
        await session.rollback()


# ---------------------------------------------------------------------------
# HTTP test client
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()
