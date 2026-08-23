"""HTTP request logging for the Robot Studio API.

Writes one line per non-quiet request to the backend log file so support can
correlate frontend Gateway timeouts with what the server actually did (or
whether it finished at all). Quiet paths (health probes) are skipped.
"""

from __future__ import annotations

import logging
import time
import uuid
from collections.abc import Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from starlette.types import ASGIApp

logger = logging.getLogger("robot_studio.request")

#: Paths that poll frequently or carry no diagnostic value.
_QUIET_SUFFIXES = (
    "/health",
)

REQUEST_ID_HEADER = "X-Request-Id"


def new_request_id() -> str:
    return uuid.uuid4().hex[:12]


def is_quiet_path(path: str) -> bool:
    return any(path.endswith(suffix) for suffix in _QUIET_SUFFIXES)


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Log method, path, status, duration, and a short request id."""

    def __init__(self, app: ASGIApp, *, quiet: Callable[[str], bool] = is_quiet_path) -> None:
        super().__init__(app)
        self._quiet = quiet

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        if request.method == "OPTIONS" or self._quiet(request.url.path):
            return await call_next(request)

        incoming = request.headers.get(REQUEST_ID_HEADER, "").strip()
        request_id = incoming or new_request_id()
        request.state.request_id = request_id

        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            logger.exception(
                "%s %s failed after %dms req=%s",
                request.method,
                request.url.path,
                elapsed_ms,
                request_id,
            )
            raise

        elapsed_ms = int((time.perf_counter() - started) * 1000)
        status = response.status_code
        message = (
            f"{request.method} {request.url.path} → {status} "
            f"({elapsed_ms}ms) req={request_id}"
        )
        if status >= 500:
            logger.error(message)
        elif status >= 400:
            logger.warning(message)
        elif elapsed_ms >= 5_000:
            logger.warning("%s [slow]", message)
        else:
            logger.info(message)

        response.headers[REQUEST_ID_HEADER] = request_id
        return response
