"""Run configuration CRUD — project-scoped named Robot execution contexts."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.run_configuration import (
    ActivateRunConfigurationRequest,
    RunConfigurationListResponse,
    RunConfigurationPatchRequest,
    RunConfigurationResponse,
    RunConfigurationWriteRequest,
)
from robot_studio.application.services.run_configuration_service import (
    RunConfigurationValidationError,
)

router = APIRouter(prefix="/run-configurations", tags=["run-configurations"])


def _http(exc: RunConfigurationValidationError) -> HTTPException:
    status = 404 if exc.code == "configuration_missing" else 400
    return HTTPException(status_code=status, detail=str(exc))


@router.get("", response_model=RunConfigurationListResponse)
async def list_run_configurations(
    gateway: RestGateway = Depends(get_gateway),
) -> RunConfigurationListResponse:
    try:
        return await gateway.list_run_configurations()
    except RunConfigurationValidationError as exc:
        raise _http(exc) from exc


@router.post("", response_model=RunConfigurationResponse)
async def create_run_configuration(
    request: RunConfigurationWriteRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> RunConfigurationResponse:
    try:
        return await gateway.create_run_configuration(request)
    except RunConfigurationValidationError as exc:
        raise _http(exc) from exc


@router.patch("/{configuration_id}", response_model=RunConfigurationResponse)
async def update_run_configuration(
    configuration_id: UUID,
    request: RunConfigurationPatchRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> RunConfigurationResponse:
    try:
        return await gateway.update_run_configuration(configuration_id, request)
    except RunConfigurationValidationError as exc:
        raise _http(exc) from exc


@router.delete("/{configuration_id}")
async def delete_run_configuration(
    configuration_id: UUID,
    gateway: RestGateway = Depends(get_gateway),
) -> dict:
    try:
        await gateway.delete_run_configuration(configuration_id)
    except RunConfigurationValidationError as exc:
        raise _http(exc) from exc
    return {"ok": True}


@router.post("/{configuration_id}/duplicate", response_model=RunConfigurationResponse)
async def duplicate_run_configuration(
    configuration_id: UUID,
    gateway: RestGateway = Depends(get_gateway),
) -> RunConfigurationResponse:
    try:
        return await gateway.duplicate_run_configuration(configuration_id)
    except RunConfigurationValidationError as exc:
        raise _http(exc) from exc


@router.post("/activate")
async def activate_run_configuration(
    request: ActivateRunConfigurationRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> dict:
    try:
        active_id = await gateway.activate_run_configuration(request.configuration_id)
    except RunConfigurationValidationError as exc:
        raise _http(exc) from exc
    return {"active_id": str(active_id) if active_id else None}
