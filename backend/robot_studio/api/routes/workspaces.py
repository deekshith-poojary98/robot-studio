from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.workspace import (
    CreateWorkspaceRequest,
    OpenWorkspaceRequest,
    RecentWorkspacesResponse,
    WorkspaceResponse,
)
from robot_studio.infrastructure.workspace.filesystem import WorkspaceValidationError

router = APIRouter(prefix="/workspaces", tags=["workspaces"])
GatewayDep = Annotated[RestGateway, Depends(get_gateway)]


def _to_response(workspace) -> WorkspaceResponse:
    return WorkspaceResponse(
        id=workspace.id,
        name=workspace.name,
        path=str(workspace.path),
        created_at=workspace.created_at,
    )


@router.post("", response_model=WorkspaceResponse, status_code=201)
async def create_workspace(
    request: CreateWorkspaceRequest,
    gateway: GatewayDep,
) -> WorkspaceResponse:
    try:
        workspace = await gateway.create_workspace(
            name=request.name,
            location=request.location,
        )
    except WorkspaceValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(workspace)


@router.post("/open", response_model=WorkspaceResponse)
async def open_workspace(
    request: OpenWorkspaceRequest,
    gateway: GatewayDep,
) -> WorkspaceResponse:
    try:
        workspace = await gateway.open_workspace(path=request.path)
    except WorkspaceValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(workspace)


@router.get("/recent", response_model=RecentWorkspacesResponse)
async def list_recent_workspaces(
    gateway: GatewayDep,
) -> RecentWorkspacesResponse:
    workspaces = await gateway.list_recent_workspaces()
    return RecentWorkspacesResponse(
        workspaces=[_to_response(item) for item in workspaces],
    )
