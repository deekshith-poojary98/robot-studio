from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.environment import (
    ActivateEnvironmentRequest,
    CloneEnvironmentRequest,
    CreateEnvironmentRequest,
    EnvironmentListResponse,
    EnvironmentResponse,
    ImportEnvironmentRequest,
    PythonInterpreterListResponse,
    PythonInterpreterResponse,
)
from robot_studio.domain.models import Environment
from robot_studio.infrastructure.environment.filesystem import (
    EnvironmentValidationError,
)

router = APIRouter(prefix="/environments", tags=["environments"])


def _to_response(environment: Environment) -> EnvironmentResponse:
    return EnvironmentResponse(
        id=environment.id,
        workspace_id=environment.workspace_id,
        name=environment.name,
        path=str(environment.path),
        python_version=environment.python_version,
        python_executable=str(environment.python_executable),
        pip_executable=str(environment.pip_executable),
        robot_executable=(
            str(environment.robot_executable) if environment.robot_executable else None
        ),
        created_at=environment.created_at,
        active=environment.is_active,
        robot_version=environment.robot_version,
        package_count=environment.package_count,
        platform=environment.platform,
        architecture=environment.architecture,
        available=environment.available,
    )


@router.get("", response_model=EnvironmentListResponse)
async def list_environments(
    sort: str = Query(default="active"),
    gateway: RestGateway = Depends(get_gateway),
) -> EnvironmentListResponse:
    try:
        environments = await gateway.list_environments(sort=sort)
    except EnvironmentValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return EnvironmentListResponse(
        environments=[_to_response(item) for item in environments],
    )


@router.get("/interpreters", response_model=PythonInterpreterListResponse)
async def list_python_interpreters(
    gateway: RestGateway = Depends(get_gateway),
) -> PythonInterpreterListResponse:
    interpreters = gateway.list_python_interpreters()
    return PythonInterpreterListResponse(
        interpreters=[
            PythonInterpreterResponse(
                path=item.path,
                version=item.version,
                display_name=item.display_name,
            )
            for item in interpreters
        ],
    )


@router.post("", response_model=EnvironmentResponse, status_code=201)
async def create_environment(
    request: CreateEnvironmentRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> EnvironmentResponse:
    try:
        environment = await gateway.create_environment(
            name=request.name,
            python_interpreter=request.python_interpreter,
            install_robot_framework=request.install_robot_framework,
        )
    except EnvironmentValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(environment)


@router.post("/import", response_model=EnvironmentResponse)
async def import_environment(
    request: ImportEnvironmentRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> EnvironmentResponse:
    try:
        environment = await gateway.import_environment(path=request.path)
    except EnvironmentValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(environment)


@router.post("/activate", response_model=EnvironmentResponse)
async def activate_environment(
    request: ActivateEnvironmentRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> EnvironmentResponse:
    try:
        environment = await gateway.activate_environment(
            environment_id=request.environment_id,
        )
    except EnvironmentValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(environment)


@router.post("/{environment_id}/clone", response_model=EnvironmentResponse, status_code=201)
async def clone_environment(
    environment_id: UUID,
    request: CloneEnvironmentRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> EnvironmentResponse:
    try:
        environment = await gateway.clone_environment(
            environment_id=environment_id,
            name=request.name,
        )
    except EnvironmentValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(environment)


@router.get("/{environment_id}", response_model=EnvironmentResponse)
async def get_environment(
    environment_id: UUID,
    gateway: RestGateway = Depends(get_gateway),
) -> EnvironmentResponse:
    try:
        environment = await gateway.get_environment(environment_id=environment_id)
    except EnvironmentValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _to_response(environment)


@router.delete("/{environment_id}", status_code=204)
async def delete_environment(
    environment_id: UUID,
    delete_files: bool = Query(default=False),
    gateway: RestGateway = Depends(get_gateway),
) -> None:
    try:
        await gateway.delete_environment(
            environment_id=environment_id,
            delete_files=delete_files,
        )
    except EnvironmentValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
