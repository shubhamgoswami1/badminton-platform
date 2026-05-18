from fastapi import HTTPException, status


class AppError(HTTPException):
    """Base application error. Maps to a specific HTTP status and error code."""

    def __init__(self, status_code: int, code: str, message: str) -> None:
        super().__init__(status_code=status_code, detail={"code": code, "message": message})
        self.code = code
        self.message = message


class NotFoundError(AppError):
    def __init__(self, message: str = "Resource not found") -> None:
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            code="NOT_FOUND",
            message=message,
        )


class ForbiddenError(AppError):
    def __init__(self, message: str = "You do not have permission to perform this action") -> None:
        super().__init__(
            status_code=status.HTTP_403_FORBIDDEN,
            code="FORBIDDEN",
            message=message,
        )


class UnauthorizedError(AppError):
    def __init__(self, message: str = "Authentication required") -> None:
        super().__init__(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="UNAUTHORIZED",
            message=message,
        )


class ConflictError(AppError):
    def __init__(self, message: str = "Request conflicts with current state") -> None:
        super().__init__(
            status_code=status.HTTP_409_CONFLICT,
            code="CONFLICT",
            message=message,
        )


class ValidationError(AppError):
    def __init__(self, message: str = "Invalid input") -> None:
        super().__init__(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="VALIDATION_ERROR",
            message=message,
        )


class TooManyRequestsError(AppError):
    def __init__(self, message: str = "Too many requests") -> None:
        super().__init__(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            code="TOO_MANY_REQUESTS",
            message=message,
        )


class SyncConflictError(Exception):
    """
    Raised when a client's score update conflicts with the current server state.

    Carries enough server state for the client to resolve the conflict without
    an extra round-trip.

    conflict_type values
    ────────────────────
    STALE_UPDATE      — client_updated_at < match.updated_at; server has a
                        newer version.  "Latest timestamp wins" rule means this
                        local update should be discarded.
    MATCH_COMPLETED   — match is already COMPLETED or WALKOVER on the server;
                        no further score mutations are permitted.
    """

    def __init__(
        self,
        conflict_type: str,
        message: str,
        server_version: int,
        server_updated_at,  # datetime
        server_status: str,
        sets: list,  # list[dict] — current SetScoreResponse dumps
    ) -> None:
        super().__init__(message)
        self.conflict_type = conflict_type
        self.message = message
        self.server_version = server_version
        self.server_updated_at = server_updated_at
        self.server_status = server_status
        self.sets = sets
