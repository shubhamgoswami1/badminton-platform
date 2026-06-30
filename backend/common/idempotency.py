"""
Idempotency key helpers — P6.

Usage (in a router endpoint):
    from common.idempotency import check_idempotency, store_idempotency

    key = request.headers.get("Idempotency-Key")
    if key:
        cached = await check_idempotency(db, key)
        if cached:
            return JSONResponse(status_code=cached["status_code"],
                                content=cached["body"])
    # ... do work ...
    response_body = ok(...)
    if key:
        await store_idempotency(db, key, 200, response_body)
    return response_body
"""

import json
from datetime import datetime, timezone, timedelta

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


_TTL_HOURS = 24


async def check_idempotency(
    db: AsyncSession,
    key: str,
) -> dict | None:
    """
    Return the cached response dict (with keys ``status_code`` and ``body``)
    if this key was seen before and the record hasn't expired.
    Returns ``None`` if no record exists.
    """
    result = await db.execute(
        text(
            "SELECT status_code, response_body, created_at "
            "FROM idempotency_records "
            "WHERE key = :key"
        ),
        {"key": key},
    )
    row = result.fetchone()
    if row is None:
        return None

    # Expire records older than TTL
    age = datetime.now(timezone.utc) - row.created_at.replace(tzinfo=timezone.utc)
    if age > timedelta(hours=_TTL_HOURS):
        # Treat as missing — client must retry with a new key after 24 h.
        return None

    return {"status_code": row.status_code, "body": row.response_body}


async def store_idempotency(
    db: AsyncSession,
    key: str,
    status_code: int,
    response_body: dict,
) -> None:
    """
    Persist the response so future requests with the same key can be served
    from the cache.  Uses INSERT ... ON CONFLICT DO NOTHING to be safe against
    concurrent duplicate requests that race through the check.
    """
    await db.execute(
        text(
            "INSERT INTO idempotency_records (key, status_code, response_body) "
            "VALUES (:key, :status_code, :body::jsonb) "
            "ON CONFLICT (key) DO NOTHING"
        ),
        {
            "key": key,
            "status_code": status_code,
            "body": json.dumps(response_body),
        },
    )
    await db.commit()
