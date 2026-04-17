"""
S3-compatible storage abstraction — stub for Phase 2 profile photo uploads.

In Phase 2, swap LocalDiskStorage for an S3Storage implementation that
wraps boto3/aiobotocore. The interface stays identical so call sites don't change.
"""

import uuid
from pathlib import Path


class StorageBackend:
    async def upload(self, key: str, data: bytes, content_type: str = "application/octet-stream") -> str:
        raise NotImplementedError

    async def delete(self, key: str) -> None:
        raise NotImplementedError

    def public_url(self, key: str) -> str:
        raise NotImplementedError


class LocalDiskStorage(StorageBackend):
    """Writes files to ./uploads/ — development only."""

    def __init__(self, base_dir: str = "uploads") -> None:
        self._base = Path(base_dir)
        self._base.mkdir(exist_ok=True)

    async def upload(self, key: str, data: bytes, content_type: str = "application/octet-stream") -> str:
        dest = self._base / key
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        return key

    async def delete(self, key: str) -> None:
        path = self._base / key
        if path.exists():
            path.unlink()

    def public_url(self, key: str) -> str:
        return f"/static/{key}"


def get_storage() -> StorageBackend:
    """Return the active storage backend. Swap implementation here for production."""
    return LocalDiskStorage()
