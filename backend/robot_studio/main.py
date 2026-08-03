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
