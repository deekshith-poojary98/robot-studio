from contextlib import asynccontextmanager
import os
import sys
from pathlib import Path

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from robot_studio import __version__
from robot_studio.api.router import api_router
from robot_studio.core.config import settings
from robot_studio.core.container import container
from robot_studio.core.database import init_database
from robot_studio.core.logging_setup import configure_logging, ensure_file_logging


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
    await container.initialize_async()
    await init_database()
    yield
    await container.shutdown()


def create_app() -> FastAPI:
    app = FastAPI(
        title="Robot Studio API",
        version=__version__,
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
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
