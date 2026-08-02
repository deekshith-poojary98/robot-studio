"""Robot Doctor REST — stable public surface under /doctor/*."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.doctor import (
    DoctorHistoryResponse,
    DoctorProfilesResponse,
    DoctorProfileResponse,
    DoctorReportResponse,
    DoctorReportSummaryResponse,
    DoctorRunRequestBody,
    FindingProviderInfoResponse,
)
from robot_studio.application.services.doctor_service import DoctorValidationError
from robot_studio.domain.models.doctor import DoctorProfileId

router = APIRouter(prefix="/doctor", tags=["doctor"])


def _http(exc: DoctorValidationError) -> HTTPException:
    msg = str(exc)
    code = 404 if "not found" in msg.lower() else 400
    return HTTPException(status_code=code, detail=msg)


@router.get("/profiles", response_model=DoctorProfilesResponse)
async def list_profiles(
    gateway: RestGateway = Depends(get_gateway),
) -> DoctorProfilesResponse:
    profiles = gateway.doctor_list_profiles()
    providers = gateway.doctor_list_providers()
    return DoctorProfilesResponse(
        profiles=[DoctorProfileResponse.from_model(p) for p in profiles],
        providers=[FindingProviderInfoResponse.from_model(p) for p in providers],
    )


@router.post("/run", response_model=DoctorReportResponse)
async def run_doctor(
    body: DoctorRunRequestBody | None = None,
    gateway: RestGateway = Depends(get_gateway),
) -> DoctorReportResponse:
    req = body or DoctorRunRequestBody()
    try:
        report = await gateway.doctor_run(
            profile=req.profile,
            project_id=UUID(req.project_id) if req.project_id else None,
            provider_ids=req.provider_ids,
        )
    except DoctorValidationError as exc:
        raise _http(exc) from exc
    return DoctorReportResponse.from_model(report)


@router.get("/report/{report_id}", response_model=DoctorReportResponse)
async def get_report(
    report_id: str,
    gateway: RestGateway = Depends(get_gateway),
) -> DoctorReportResponse:
    try:
        report = await gateway.doctor_get_report(report_id)
    except DoctorValidationError as exc:
        raise _http(exc) from exc
    return DoctorReportResponse.from_model(report)


@router.get("/history", response_model=DoctorHistoryResponse)
async def doctor_history(
    project_id: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    gateway: RestGateway = Depends(get_gateway),
) -> DoctorHistoryResponse:
    try:
        items = await gateway.doctor_history(
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except DoctorValidationError as exc:
        raise _http(exc) from exc
    return DoctorHistoryResponse(
        items=[DoctorReportSummaryResponse.from_model(i) for i in items],
    )


# Keep profile enum discoverable in OpenAPI via unused import reference
_ = DoctorProfileId
