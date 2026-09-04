from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.report import (
    DashboardResponse,
    OpenArtifactResponse,
    RunListResponse,
    RunResponse,
    to_dashboard_response,
    to_run_response,
)
from robot_studio.application.services.report_service import ReportValidationError

router = APIRouter(prefix="/reports", tags=["reports"])
GatewayDep = Annotated[RestGateway, Depends(get_gateway)]


@router.get("/dashboard", response_model=DashboardResponse)
async def get_dashboard(
    gateway: GatewayDep,
) -> DashboardResponse:
    try:
        summary = await gateway.get_reports_dashboard()
    except ReportValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_dashboard_response(summary)


@router.get("", response_model=RunListResponse)
async def list_reports(
    gateway: GatewayDep,
) -> RunListResponse:
    try:
        runs = await gateway.list_reports()
    except ReportValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return RunListResponse(runs=[to_run_response(run) for run in runs])


@router.get("/{run_id}", response_model=RunResponse)
async def get_report(
    run_id: UUID,
    gateway: GatewayDep,
) -> RunResponse:
    try:
        run = await gateway.get_report(run_id)
    except ReportValidationError as exc:
        message = str(exc)
        status = 404 if "not found" in message.lower() else 400
        raise HTTPException(status_code=status, detail=message) from exc
    return to_run_response(run)


@router.delete("/{run_id}", status_code=204)
async def delete_report(
    run_id: UUID,
    gateway: GatewayDep,
) -> None:
    try:
        await gateway.delete_report(run_id)
    except ReportValidationError as exc:
        message = str(exc)
        status = 404 if "not found" in message.lower() else 400
        raise HTTPException(status_code=status, detail=message) from exc


@router.post("/{run_id}/open-log", response_model=OpenArtifactResponse)
async def open_log(
    run_id: UUID,
    gateway: GatewayDep,
) -> OpenArtifactResponse:
    try:
        path = await gateway.open_report_log(run_id)
    except ReportValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return OpenArtifactResponse(path=str(path))


@router.post("/{run_id}/open-report", response_model=OpenArtifactResponse)
async def open_report(
    run_id: UUID,
    gateway: GatewayDep,
) -> OpenArtifactResponse:
    try:
        path = await gateway.open_report_html(run_id)
    except ReportValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return OpenArtifactResponse(path=str(path))


@router.post("/{run_id}/open-xml", response_model=OpenArtifactResponse)
async def open_xml(
    run_id: UUID,
    gateway: GatewayDep,
) -> OpenArtifactResponse:
    try:
        path = await gateway.open_report_xml(run_id)
    except ReportValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return OpenArtifactResponse(path=str(path))


@router.post("/{run_id}/reveal", response_model=OpenArtifactResponse)
async def reveal_report(
    run_id: UUID,
    gateway: GatewayDep,
) -> OpenArtifactResponse:
    try:
        path = await gateway.reveal_report(run_id)
    except ReportValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return OpenArtifactResponse(path=str(path))
