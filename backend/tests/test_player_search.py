"""
Player search tests — GET /api/v1/users/search

Covers:
  - no filters → returns all profiles
  - text search on display_name
  - text search on city
  - skill_level filter
  - play_style filter
  - min_rating / max_rating range
  - radius bounding-box filter (lat/lng/radius_km)
  - profiles without a rating are excluded from rating range queries
  - unauthenticated request → 401
  - reliability_score default is 5.0 on new profiles
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from users.models import PlayerProfile

PHONE_BASE = "+9180000000"


async def _login(client: AsyncClient, phone: str) -> str:
    await client.post("/api/v1/auth/otp/request", json={"phone_number": phone})
    r = await client.post(
        "/api/v1/auth/otp/verify", json={"phone_number": phone, "otp": "123456"}
    )
    return r.json()["data"]["access_token"]


async def _create_profile(client: AsyncClient, token: str, **kwargs) -> None:
    await client.put(
        "/api/v1/users/me/profile",
        json=kwargs,
        headers={"Authorization": f"Bearer {token}"},
    )


# ── Fixtures ──────────────────────────────────────────────────────────────


@pytest.fixture(autouse=True)
async def seed_players(client: AsyncClient, db_session: AsyncSession):
    """
    Create three distinct player profiles before each test in this module.

      Alice  – ADVANCED  / SINGLES / Mumbai  / rating=8.0  / lat=19.07, lng=72.87
      Bob    – BEGINNER  / DOUBLES / Delhi   / rating=3.5  / lat=28.61, lng=77.23
      Carol  – ADVANCED  / BOTH    / Mumbai  / rating=None / no GPS
    """
    t_alice = await _login(client, PHONE_BASE + "01")
    t_bob   = await _login(client, PHONE_BASE + "02")
    t_carol = await _login(client, PHONE_BASE + "03")

    await _create_profile(
        client, t_alice,
        display_name="Alice Sharma",
        city="Mumbai",
        skill_level="ADVANCED",
        play_style="SINGLES",
        rating=8.0,
        latitude=19.0760,
        longitude=72.8777,
    )
    await _create_profile(
        client, t_bob,
        display_name="Bob Kumar",
        city="Delhi",
        skill_level="BEGINNER",
        play_style="DOUBLES",
        rating=3.5,
        latitude=28.6139,
        longitude=77.2090,
    )
    await _create_profile(
        client, t_carol,
        display_name="Carol Nair",
        city="Mumbai",
        skill_level="ADVANCED",
        play_style="BOTH",
        # no rating, no GPS
    )


# ── Helpers ───────────────────────────────────────────────────────────────


async def _search(client: AsyncClient, token: str, **params) -> dict:
    r = await client.get(
        "/api/v1/users/search",
        params=params,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200, r.text
    return r.json()["data"]


# ── Tests ─────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_search_no_filters_returns_all_profiles(client: AsyncClient):
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(client, token)
    assert data["total"] == 3
    names = {p["display_name"] for p in data["items"]}
    assert names == {"Alice Sharma", "Bob Kumar", "Carol Nair"}


@pytest.mark.asyncio
async def test_search_text_query_matches_display_name(client: AsyncClient):
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(client, token, q="alice")
    assert data["total"] == 1
    assert data["items"][0]["display_name"] == "Alice Sharma"


@pytest.mark.asyncio
async def test_search_text_query_matches_city(client: AsyncClient):
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(client, token, q="mumbai")
    assert data["total"] == 2
    names = {p["display_name"] for p in data["items"]}
    assert names == {"Alice Sharma", "Carol Nair"}


@pytest.mark.asyncio
async def test_search_skill_level_filter(client: AsyncClient):
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(client, token, skill_level="ADVANCED")
    assert data["total"] == 2
    for p in data["items"]:
        assert p["skill_level"] == "ADVANCED"


@pytest.mark.asyncio
async def test_search_play_style_filter(client: AsyncClient):
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(client, token, play_style="DOUBLES")
    assert data["total"] == 1
    assert data["items"][0]["display_name"] == "Bob Kumar"


@pytest.mark.asyncio
async def test_search_min_rating_excludes_profiles_without_rating(client: AsyncClient):
    token = await _login(client, PHONE_BASE + "01")
    # Carol has no rating — must be excluded
    data = await _search(client, token, min_rating=1.0)
    names = {p["display_name"] for p in data["items"]}
    assert "Carol Nair" not in names
    assert data["total"] == 2


@pytest.mark.asyncio
async def test_search_rating_range_filter(client: AsyncClient):
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(client, token, min_rating=7.0, max_rating=10.0)
    assert data["total"] == 1
    assert data["items"][0]["display_name"] == "Alice Sharma"
    assert data["items"][0]["rating"] == 8.0


@pytest.mark.asyncio
async def test_search_rating_range_no_match(client: AsyncClient):
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(client, token, min_rating=9.5, max_rating=10.0)
    assert data["total"] == 0


@pytest.mark.asyncio
async def test_search_radius_filter_includes_nearby(client: AsyncClient):
    """Profiles within ~50 km of central Mumbai should include Alice but not Bob (Delhi)."""
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(
        client, token,
        lat=19.076,
        lng=72.878,
        radius_km=50,
    )
    names = {p["display_name"] for p in data["items"]}
    assert "Alice Sharma" in names
    assert "Bob Kumar" not in names


@pytest.mark.asyncio
async def test_search_radius_excludes_profiles_without_gps(client: AsyncClient):
    """Carol has no GPS coords — must not appear in a radius search."""
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(
        client, token,
        lat=19.076,
        lng=72.878,
        radius_km=50,
    )
    names = {p["display_name"] for p in data["items"]}
    assert "Carol Nair" not in names


@pytest.mark.asyncio
async def test_search_combined_filters(client: AsyncClient):
    """ADVANCED + Mumbai text → Alice and Carol; then min_rating=5.0 → only Alice."""
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(client, token, q="mumbai", skill_level="ADVANCED", min_rating=5.0)
    assert data["total"] == 1
    assert data["items"][0]["display_name"] == "Alice Sharma"


@pytest.mark.asyncio
async def test_search_pagination(client: AsyncClient):
    token = await _login(client, PHONE_BASE + "01")
    data = await _search(client, token, page=1, page_size=2)
    assert len(data["items"]) == 2
    assert data["total"] == 3
    assert data["pages"] == 2


@pytest.mark.asyncio
async def test_search_requires_auth(client: AsyncClient):
    r = await client.get("/api/v1/users/search")
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_new_profile_has_default_reliability_score(
    client: AsyncClient, db_session: AsyncSession
):
    """A freshly created profile must have reliability_score = 5.0."""
    token = await _login(client, PHONE_BASE + "04")
    await _create_profile(client, token, display_name="Dave")
    r = await client.put(
        "/api/v1/users/me/profile",
        json={"display_name": "Dave"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200
    assert r.json()["data"]["reliability_score"] == 5.0


@pytest.mark.asyncio
async def test_update_profile_with_location(client: AsyncClient):
    """Saving lat/lng roundtrips correctly."""
    token = await _login(client, PHONE_BASE + "05")
    r = await client.put(
        "/api/v1/users/me/profile",
        json={
            "display_name": "Eve",
            "latitude": 12.9716,
            "longitude": 77.5946,
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200
    data = r.json()["data"]
    assert abs(data["latitude"] - 12.9716) < 1e-4
    assert abs(data["longitude"] - 77.5946) < 1e-4


@pytest.mark.asyncio
async def test_update_profile_lat_without_lng_rejected(client: AsyncClient):
    """Providing only latitude (no longitude) must return 400."""
    token = await _login(client, PHONE_BASE + "06")
    r = await client.put(
        "/api/v1/users/me/profile",
        json={"display_name": "Frank", "latitude": 19.0760},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 400
