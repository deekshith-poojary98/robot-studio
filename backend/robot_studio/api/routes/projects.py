from fastapi import APIRouter, Depends, HTTPException

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.project import (
    CreateProjectRequest,
    CreateStandaloneProjectRequest,
    DetectedEnvironment,
    ImportProjectRequest,
    OpenProjectByPathRequest,
    OpenProjectByPathResponse,
    OpenProjectRequest,
    ProjectListResponse,
    ProjectResponse,
)
from robot_studio.api.schemas.workspace import WorkspaceResponse
from robot_studio.domain.models import Project
from robot_studio.infrastructure.project.filesystem import ProjectValidationError
from robot_studio.infrastructure.workspace.filesystem import WorkspaceValidationError

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


def _open_path_response(
    workspace,
    project: Project,
    *,
    needs_environment: bool,
    detected_environments: list[dict[str, str]],
) -> OpenProjectByPathResponse:
    return OpenProjectByPathResponse(
        workspace=WorkspaceResponse(
            id=workspace.id,
            name=workspace.name,
            path=str(workspace.path),
            created_at=workspace.created_at,
        ),
        project=_to_response(project),
        needs_environment=needs_environment,
        detected_environments=[
            DetectedEnvironment(name=item["name"], path=item["path"])
            for item in detected_environments
        ],
    )


@router.post("", response_model=ProjectResponse, status_code=201)
async def create_project(
    request: CreateProjectRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ProjectResponse:
    try:
        project = await gateway.create_project(
            name=request.name,
        )
    except ProjectValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(project)


@router.post("/standalone", response_model=OpenProjectByPathResponse, status_code=201)
async def create_standalone_project(
    request: CreateStandaloneProjectRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> OpenProjectByPathResponse:
    try:
        workspace, project = await gateway.create_standalone_project(
            name=request.name,
            location=request.location,
        )
    except (ProjectValidationError, WorkspaceValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    needs, detected = await gateway.environment_prompt_state()
    return _open_path_response(
        workspace,
        project,
        needs_environment=needs,
        detected_environments=detected,
    )


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


@router.post("/open-path", response_model=OpenProjectByPathResponse)
async def open_project_by_path(
    request: OpenProjectByPathRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> OpenProjectByPathResponse:
    try:
        workspace, project = await gateway.open_project_by_path(
            path=request.path,
            force=request.force,
        )
    except (ProjectValidationError, WorkspaceValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    needs, detected = await gateway.environment_prompt_state()
    return _open_path_response(
        workspace,
        project,
        needs_environment=needs,
        detected_environments=detected,
    )


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
