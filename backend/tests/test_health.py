import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health_returns_200(client: AsyncClient) -> None:
    # /health/live is the unauthenticated liveness probe; /health requires a token
    response = await client.get("/api/v1/health/live")
    assert response.status_code == 200
    body = response.json()
    assert body["data"]["status"] == "ok"
    assert body["error"] is None
