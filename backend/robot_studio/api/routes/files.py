from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.files import (
    DirectoryCreateRequest,
    FileContentResponse,
    FileCreateRequest,
    FileMoveRequest,
    FileMutationResponse,
    FilePathRequest,
    FileRenameRequest,
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


@router.post("/create", response_model=FileMutationResponse)
async def create_file(
    request: FileCreateRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> FileMutationResponse:
    try:
        result = await gateway.create_file(request.path, request.content)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileMutationResponse(
        path=result["path"],
        mtime=result.get("mtime"),
        size=result.get("size"),
        saved_at=result.get("saved_at"),
    )


@router.post("/mkdir", response_model=FileMutationResponse)
async def create_directory(
    request: DirectoryCreateRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> FileMutationResponse:
    try:
        result = await gateway.create_directory(request.path)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileMutationResponse(**result)


@router.post("/rename", response_model=FileMutationResponse)
async def rename_path(
    request: FileRenameRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> FileMutationResponse:
    try:
        result = await gateway.rename_path(request.path, request.new_name)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileMutationResponse(**result)


@router.post("/move", response_model=FileMutationResponse)
async def move_path(
    request: FileMoveRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> FileMutationResponse:
    try:
        result = await gateway.move_path(request.path, request.destination_dir)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileMutationResponse(**result)


@router.post("/duplicate", response_model=FileMutationResponse)
async def duplicate_path(
    request: FilePathRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> FileMutationResponse:
    try:
        result = await gateway.duplicate_path(request.path)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileMutationResponse(**result)


@router.post("/delete", response_model=FileMutationResponse)
async def delete_path(
    request: FilePathRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> FileMutationResponse:
    try:
        result = await gateway.delete_path(request.path)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileMutationResponse(**result)


@router.get("/tree", response_model=FileTreeResponse)
async def list_tree(
    path: str | None = Query(default=None),
    depth: int = Query(default=0, ge=0, le=8),
    gateway: RestGateway = Depends(get_gateway),
) -> FileTreeResponse:
    try:
        entries = await gateway.list_file_tree(path=path, depth=depth)
    except FileValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FileTreeResponse(entries=[FileTreeNode.model_validate(item) for item in entries])
