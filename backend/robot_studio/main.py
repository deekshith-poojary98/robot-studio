import asyncio
import logging
import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from fastapi import FastAPI, Request
from fastapi.exception_handlers import (
    http_exception_handler,
    request_validation_exception_handler,
)
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from starlette.exceptions import HTTPException as StarletteHTTPException

from robot_studio import __version__
from robot_studio.api.router import api_router
from robot_studio.core.config import settings
from robot_studio.core.container import container
from robot_studio.core.database import init_database
from robot_studio.core.logging_setup import configure_logging, ensure_file_logging
from robot_studio.core.request_logging import RequestLoggingMiddleware
from robot_studio.infrastructure.process_utils import (
    init_blocking_pool,
    shutdown_blocking_pool,
)

_log = logging.getLogger("robot_studio")


def _ensure_process_cwd() -> None:
    """Heal a deleted process cwd so child pip/venv calls do not crash."""
    try:
        Path.cwd()
        return
    except OSError:
        pass
    for candidate in (settings.data_dir, Path.home(), Path("/")):
        try:
            candidate.mkdir(parents=True, exist_ok=True)
            os.chdir(candidate)
            Path.cwd()
            return
        except OSError:
            continue


@asynccontextmanager
async def lifespan(_app: FastAPI):
    _ensure_process_cwd()
    # Uvicorn may reconfigure logging after import-time setup — re-attach file log.
    ensure_file_logging(settings.data_dir)
    loop = asyncio.get_running_loop()
    init_blocking_pool(loop=loop)
    await container.initialize_async()
    await init_database()
    yield
    await container.shutdown()
    shutdown_blocking_pool()


def create_app() -> FastAPI:
    app = FastAPI(
        title="Robot Studio API",
        version=__version__,
        lifespan=lifespan,
    )

    # CORS outermost so preflight still works; request logging inside CORS.
    app.add_middleware(RequestLoggingMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.exception_handler(Exception)
    async def unhandled_exception(request: Request, exc: Exception) -> Response:
        # Delegate known HTTP/validation errors so status codes stay correct.
        if isinstance(exc, StarletteHTTPException):
            return await http_exception_handler(request, exc)
        if isinstance(exc, RequestValidationError):
            return await request_validation_exception_handler(request, exc)

        request_id = getattr(request.state, "request_id", None)
        _log.exception(
            "Unhandled error on %s %s req=%s: %s",
            request.method,
            request.url.path,
            request_id or "-",
            exc,
        )
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"},
        )

    app.include_router(api_router, prefix=settings.api_prefix)
    return app


app = create_app()


def _is_frozen() -> bool:
    return bool(getattr(sys, "frozen", False))


def main() -> None:
    # Required for ProcessPool / spawn under the frozen Windows sidecar.
    import multiprocessing

    multiprocessing.freeze_support()
    # File logging before uvicorn so access/error lines land on disk too.
    configure_logging(settings.data_dir)
    # Pass the app object when frozen so PyInstaller does not need the
    # "robot_studio.main:app" string import path.
    if _is_frozen() or not settings.debug:
        uvicorn.run(
            app,
            host=settings.host,
            port=settings.port,
            reload=False,
        )
        return
    uvicorn.run(
        "robot_studio.main:app",
        host=settings.host,
        port=settings.port,
        reload=True,
    )


if __name__ == "__main__":
    main()
