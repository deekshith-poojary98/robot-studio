from fastapi import APIRouter

from robot_studio.api.routes import (
    environments,
    execution,
    health,
    index,
    language,
    packages,
    projects,
    reports,
    workspaces,
)

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(workspaces.router)
api_router.include_router(projects.router)
api_router.include_router(environments.router)
api_router.include_router(packages.router)
api_router.include_router(execution.router)
api_router.include_router(reports.router)
api_router.include_router(index.router)
api_router.include_router(index.search_router)
api_router.include_router(language.router)
