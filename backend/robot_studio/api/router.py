from fastapi import APIRouter

from robot_studio.api.routes import (
    environments,
    execution,
    files,
    health,
    index,
    language,
    packages,
    plugins,
    projects,
    git,
    reports,
    tests,
    workspaces,
)

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(workspaces.router)
api_router.include_router(projects.router)
api_router.include_router(environments.router)
api_router.include_router(packages.router)
api_router.include_router(execution.router)
api_router.include_router(tests.router)
api_router.include_router(reports.router)
api_router.include_router(index.router)
api_router.include_router(index.search_router)
api_router.include_router(language.router)
api_router.include_router(files.router)
api_router.include_router(plugins.router)
api_router.include_router(git.router)
