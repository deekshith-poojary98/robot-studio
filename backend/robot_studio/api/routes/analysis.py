"""Analysis + Inspection REST — infrastructure APIs only (no UI).

Layering:
  Analysis Engine (graph) → Inspection Engine (Findings) → REST

Feature-specific Doctor checks are exposed only as inspections that return
``Finding`` rows — not as one-off endpoints.
"""

from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.analysis import (
    AffectedTestsRequest,
    AnalysisSnapshotResponse,
    DependencyGraphResponse,
    DependencyNodeResponse,
    EdgeListResponse,
    EdgeRefResponse,
    EntityListResponse,
    EntityRefResponse,
    InspectionInfoResponse,
    InspectionListResponse,
    InspectionReportResponse,
    InspectRequest,
    UsageStatResponse,
    UsageStatsResponse,
)
from robot_studio.application.services.analysis_service import AnalysisValidationError

router = APIRouter(prefix="/analysis", tags=["analysis"])
GatewayDep = Annotated[RestGateway, Depends(get_gateway)]


def _http(exc: AnalysisValidationError) -> HTTPException:
    return HTTPException(status_code=400, detail=str(exc))


@router.get("/snapshot", response_model=AnalysisSnapshotResponse)
async def analysis_snapshot(
    gateway: GatewayDep,
    project_id: Annotated[str | None, Query()] = None,
) -> AnalysisSnapshotResponse:
    try:
        snap = await gateway.analysis_snapshot(
            UUID(project_id) if project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return AnalysisSnapshotResponse.from_model(snap)


@router.post("/rebuild", response_model=AnalysisSnapshotResponse)
async def analysis_rebuild(
    gateway: GatewayDep,
    project_id: Annotated[str | None, Query()] = None,
) -> AnalysisSnapshotResponse:
    try:
        snap = await gateway.analysis_rebuild(
            UUID(project_id) if project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return AnalysisSnapshotResponse.from_model(snap)


# --- Inspection Engine ---


@router.get("/inspections", response_model=InspectionListResponse)
async def list_inspections(
    gateway: GatewayDep,
) -> InspectionListResponse:
    infos = gateway.analysis_list_inspections()
    return InspectionListResponse(
        inspections=[InspectionInfoResponse.from_model(i) for i in infos],
    )


@router.post("/inspect", response_model=InspectionReportResponse)
async def run_inspections(
    body: InspectRequest,
    gateway: GatewayDep,
) -> InspectionReportResponse:
    try:
        report = await gateway.analysis_inspect(
            inspection_ids=body.inspection_ids,
            project_id=UUID(body.project_id) if body.project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return InspectionReportResponse.from_model(report)


@router.get("/inspect/{inspection_id}", response_model=InspectionReportResponse)
async def run_one_inspection(
    inspection_id: str,
    gateway: GatewayDep,
    project_id: Annotated[str | None, Query()] = None,
) -> InspectionReportResponse:
    try:
        report = await gateway.analysis_inspect_one(
            inspection_id,
            UUID(project_id) if project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return InspectionReportResponse.from_model(report)


# --- Graph query API (Impact / Rename / AI — not Doctor findings) ---


@router.get("/graph/keyword-callers", response_model=EdgeListResponse)
async def keyword_callers(
    gateway: GatewayDep,
    keyword: Annotated[str, Query()],
    project_id: Annotated[str | None, Query()] = None,
) -> EdgeListResponse:
    try:
        items = await gateway.analysis_keyword_callers(
            keyword,
            UUID(project_id) if project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return EdgeListResponse(items=[EdgeRefResponse.from_model(i) for i in items])


@router.get("/graph/keyword-callees", response_model=EdgeListResponse)
async def keyword_callees(
    gateway: GatewayDep,
    keyword: Annotated[str, Query()],
    project_id: Annotated[str | None, Query()] = None,
) -> EdgeListResponse:
    try:
        items = await gateway.analysis_keyword_callees(
            keyword,
            UUID(project_id) if project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return EdgeListResponse(items=[EdgeRefResponse.from_model(i) for i in items])


@router.get("/graph/dependency", response_model=DependencyGraphResponse)
async def dependency_graph(
    gateway: GatewayDep,
    project_id: Annotated[str | None, Query()] = None,
) -> DependencyGraphResponse:
    try:
        nodes = await gateway.analysis_dependency_graph(
            UUID(project_id) if project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return DependencyGraphResponse(
        nodes=[DependencyNodeResponse.from_model(n) for n in nodes],
    )


@router.post("/graph/affected-tests", response_model=EntityListResponse)
async def affected_tests(
    body: AffectedTestsRequest,
    gateway: GatewayDep,
) -> EntityListResponse:
    try:
        items = await gateway.analysis_affected_tests(
            changed_files=body.changed_files or None,
            changed_symbols=body.changed_symbols or None,
            project_id=UUID(body.project_id) if body.project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return EntityListResponse(items=[EntityRefResponse.from_model(i) for i in items])


@router.get("/graph/variable-references", response_model=EdgeListResponse)
async def variable_references(
    gateway: GatewayDep,
    variable: Annotated[str, Query()],
    project_id: Annotated[str | None, Query()] = None,
) -> EdgeListResponse:
    try:
        items = await gateway.analysis_variable_references(
            variable,
            UUID(project_id) if project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return EdgeListResponse(items=[EdgeRefResponse.from_model(i) for i in items])


@router.get("/graph/library-usage", response_model=EdgeListResponse)
async def library_usage(
    gateway: GatewayDep,
    library: Annotated[str | None, Query()] = None,
    project_id: Annotated[str | None, Query()] = None,
) -> EdgeListResponse:
    try:
        items = await gateway.analysis_library_usage(
            library,
            UUID(project_id) if project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return EdgeListResponse(items=[EdgeRefResponse.from_model(i) for i in items])


@router.get("/graph/keyword-usage-statistics", response_model=UsageStatsResponse)
async def keyword_usage_statistics(
    gateway: GatewayDep,
    project_id: Annotated[str | None, Query()] = None,
) -> UsageStatsResponse:
    try:
        items = await gateway.analysis_keyword_usage_statistics(
            UUID(project_id) if project_id else None,
        )
    except AnalysisValidationError as exc:
        raise _http(exc) from exc
    return UsageStatsResponse(items=[UsageStatResponse.from_model(i) for i in items])
