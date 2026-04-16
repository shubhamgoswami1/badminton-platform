"""
Shared pytest fixtures for all backend tests.

Assumptions:
- Tests run against a real PostgreSQL instance (not mocked).
- The test DB URL is provided via TEST_DATABASE_URL env var; falls back to the
  default DATABASE_URL with the database name suffixed by "_test".
- Each test function gets a clean DB session that is rolled back after the test.
  Full table truncation between test modules is handled by the session-scoped
  `reset_db` fixture (added in P1 once tables exist).

Usage:
    pytest tests/
"""

import os

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from config import get_settings
from database import Base, get_db
from main import app

settings = get_settings()

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    settings.database_url.replace("/badminton", "/badminton_test"),
)

test_engine = create_async_engine(TEST_DATABASE_URL, echo=False, pool_pre_ping=True)
TestSessionLocal = async_sessionmaker(
    bind=test_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
    autocommit=False,
)


@pytest_asyncio.fixture(scope="session", autouse=True)
async def create_test_tables():
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


@pytest_asyncio.fixture
async def db_session() -> AsyncSession:
    async with TestSessionLocal() as session:
        yield session
        await session.rollback()


@pytest_asyncio.fixture
async def client(db_session: AsyncSession) -> AsyncClient:
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()
