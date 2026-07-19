from fastapi import APIRouter, Depends, HTTPException

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.project import (
    CreateProjectRequest,
    ImportProjectRequest,
    OpenProjectRequest,
    ProjectListResponse,
    ProjectResponse,
)
from robot_studio.domain.models import Project
from robot_studio.infrastructure.project.filesystem import ProjectValidationError

router = APIRouter(prefix="/projects", tags=["projects"])


def _to_response(project: Project) -> ProjectResponse:
    return ProjectResponse(
        id=project.id,
        workspace_id=project.workspace_id,
        name=project.name,
        path=str(project.path),
        type=project.type,
        created_at=project.created_at,
    )


@router.post("", response_model=ProjectResponse, status_code=201)
async def create_project(
    request: CreateProjectRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ProjectResponse:
    try:
        project = await gateway.create_project(
            name=request.name,
            project_type=request.type,
        )
    except ProjectValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(project)


@router.post("/import", response_model=ProjectResponse)
async def import_project(
    request: ImportProjectRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ProjectResponse:
    try:
        project = await gateway.import_project(path=request.path)
    except ProjectValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(project)


@router.post("/open", response_model=ProjectResponse)
async def open_project(
    request: OpenProjectRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ProjectResponse:
    try:
        project = await gateway.open_project(project_id=request.project_id)
    except ProjectValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(project)


@router.get("", response_model=ProjectListResponse)
async def list_projects(
    gateway: RestGateway = Depends(get_gateway),
) -> ProjectListResponse:
    try:
        projects = await gateway.list_projects()
    except ProjectValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return ProjectListResponse(projects=[_to_response(item) for item in projects])


@router.get("/recent", response_model=ProjectListResponse)
async def list_recent_projects(
    gateway: RestGateway = Depends(get_gateway),
) -> ProjectListResponse:
    projects = await gateway.list_recent_projects()
    return ProjectListResponse(projects=[_to_response(item) for item in projects])
