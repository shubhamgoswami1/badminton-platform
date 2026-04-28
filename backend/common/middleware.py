"""Request ID middleware — injects a UUID per request into structlog context.

Implemented as a pure-ASGI middleware (not BaseHTTPMiddleware) to avoid the
asyncio task-group / event-loop incompatibility that arises in Python 3.12+
when BaseHTTPMiddleware is used with pytest-asyncio's ASGITransport.
"""

import uuid

import structlog
from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Receive, Scope, Send


class RequestIdMiddleware:
    """Attach a UUID to every HTTP request and expose it as X-Request-ID."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_id = str(uuid.uuid4())

        async def send_with_request_id(message: dict) -> None:
            if message["type"] == "http.response.start":
                headers = MutableHeaders(scope=message)
                headers.append("X-Request-ID", request_id)
            await send(message)

        with structlog.contextvars.bound_contextvars(request_id=request_id):
            await self.app(scope, receive, send_with_request_id)
