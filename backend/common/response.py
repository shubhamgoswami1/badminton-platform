from typing import Any, Generic, TypeVar

from pydantic import BaseModel

DataT = TypeVar("DataT")


class ErrorBody(BaseModel):
    code: str
    message: str


class Meta(BaseModel):
    pass


class ApiResponse(BaseModel, Generic[DataT]):
    data: DataT | None = None
    error: ErrorBody | None = None
    meta: dict[str, Any] = {}


def ok(data: Any, meta: dict[str, Any] | None = None) -> dict[str, Any]:
    return {"data": data, "error": None, "meta": meta or {}}


def error(code: str, message: str) -> dict[str, Any]:
    return {"data": None, "error": {"code": code, "message": message}, "meta": {}}
