from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from robot_studio import __version__
from robot_studio.api.router import api_router
from robot_studio.core.config import settings
from robot_studio.core.container import container
from robot_studio.core.database import init_database


@asynccontextmanager
async def lifespan(_app: FastAPI):
    await container.initialize_async()
    await init_database()
    yield


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


def main() -> None:
    uvicorn.run(
        "robot_studio.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )


if __name__ == "__main__":
    main()
