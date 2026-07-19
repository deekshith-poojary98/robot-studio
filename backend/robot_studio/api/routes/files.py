from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.files import (
    FileContentResponse,
    FileTreeNode,
    FileTreeResponse,
    FileWriteRequest,
    FileWriteResponse,
)
from robot_studio.application.services.file_service import FileValidationError

router = APIRouter(prefix="/files", tags=["files"])


@router.get("/content", response_model=FileContentResponse)
async def read_file(
    path: str = Query(min_length=1),
    gateway: RestGateway = Depends(get_gateway),
) -> FileContentResponse:
    try:
        result = await gateway.read_file(path)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileContentResponse(**result)


@router.put("/content", response_model=FileWriteResponse)
async def write_file(
    request: FileWriteRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> FileWriteResponse:
    try:
        result = await gateway.write_file(request.path, request.content)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileWriteResponse(**result)


@router.get("/tree", response_model=FileTreeResponse)
async def list_tree(
    path: str | None = Query(default=None),
    depth: int = Query(default=3, ge=0, le=8),
    gateway: RestGateway = Depends(get_gateway),
) -> FileTreeResponse:
    try:
        entries = await gateway.list_file_tree(path=path, depth=depth)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileTreeResponse(entries=[FileTreeNode.model_validate(item) for item in entries])
