import math
from typing import Any, Generic, TypeVar

from fastapi import Query
from pydantic import BaseModel

ItemT = TypeVar("ItemT")

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 100


class PageParams:
    def __init__(
        self,
        page: int = Query(default=1, ge=1, description="Page number (1-based)"),
        page_size: int = Query(default=DEFAULT_PAGE_SIZE, ge=1, le=MAX_PAGE_SIZE),
    ) -> None:
        self.page = page
        self.page_size = page_size

    @property
    def offset(self) -> int:
        return (self.page - 1) * self.page_size

    @property
    def limit(self) -> int:
        return self.page_size


class PageMeta(BaseModel):
    page: int
    page_size: int
    total: int
    total_pages: int


class PagedResponse(BaseModel, Generic[ItemT]):
    data: list[ItemT]
    error: Any = None
    meta: PageMeta


def paginate(items: list[Any], total: int, params: PageParams) -> dict[str, Any]:
    return {
        "data": items,
        "error": None,
        "meta": {
            "page": params.page,
            "page_size": params.page_size,
            "total": total,
            "total_pages": math.ceil(total / params.page_size) if total > 0 else 0,
        },
    }
