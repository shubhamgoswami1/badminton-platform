import pytest
from httpx import AsyncClient


PHONE = "+911111111111"


async def _login(client: AsyncClient, phone: str = PHONE) -> dict:
    await client.post("/api/v1/auth/otp/request", json={"phone_number": phone})
    r = await client.post("/api/v1/auth/otp/verify", json={"phone_number": phone, "otp": "123456"})
    return r.json()["data"]


@pytest.mark.asyncio
async def test_get_me_returns_user_and_empty_profile(client: AsyncClient) -> None:
    tokens = await _login(client)
    r = await client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {tokens['access_token']}"})
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["user"]["phone_number"] == PHONE
    assert data["profile"] is None


@pytest.mark.asyncio
async def test_put_profile_creates_profile(client: AsyncClient) -> None:
    tokens = await _login(client)
    hdrs = {"Authorization": f"Bearer {tokens['access_token']}"}
    r = await client.put("/api/v1/users/me/profile", json={"display_name": "Alice", "city": "Chennai"}, headers=hdrs)
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["display_name"] == "Alice"
    assert data["city"] == "Chennai"


@pytest.mark.asyncio
async def test_put_profile_updates_existing(client: AsyncClient) -> None:
    tokens = await _login(client)
    hdrs = {"Authorization": f"Bearer {tokens['access_token']}"}
    await client.put("/api/v1/users/me/profile", json={"display_name": "Alice"}, headers=hdrs)
    r = await client.put("/api/v1/users/me/profile", json={"display_name": "Alice Updated", "skill_level": "ADVANCED"}, headers=hdrs)
    assert r.status_code == 200
    assert r.json()["data"]["display_name"] == "Alice Updated"
    assert r.json()["data"]["skill_level"] == "ADVANCED"


@pytest.mark.asyncio
async def test_get_other_user_profile(client: AsyncClient) -> None:
    t1 = await _login(client, "+911111111112")
    t2 = await _login(client, "+911111111113")
    # user2 creates a profile
    await client.put("/api/v1/users/me/profile", json={"display_name": "Bob"},
                     headers={"Authorization": f"Bearer {t2['access_token']}"})
    # user1 fetches user2's profile
    me_r = await client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {t2['access_token']}"})
    user2_id = me_r.json()["data"]["user"]["id"]
    r = await client.get(f"/api/v1/users/{user2_id}/profile",
                         headers={"Authorization": f"Bearer {t1['access_token']}"})
    assert r.status_code == 200
    assert r.json()["data"]["display_name"] == "Bob"


@pytest.mark.asyncio
async def test_get_unknown_user_profile_returns_404(client: AsyncClient) -> None:
    tokens = await _login(client)
    hdrs = {"Authorization": f"Bearer {tokens['access_token']}"}
    r = await client.get("/api/v1/users/00000000-0000-0000-0000-000000000001/profile", headers=hdrs)
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_all_user_endpoints_require_auth(client: AsyncClient) -> None:
    r1 = await client.get("/api/v1/users/me")
    r2 = await client.put("/api/v1/users/me/profile", json={"display_name": "X"})
    r3 = await client.get("/api/v1/users/00000000-0000-0000-0000-000000000001/profile")
    assert r1.status_code == 401
    assert r2.status_code == 401
    assert r3.status_code == 401
