"""Execution knowledge REST — /analysis/execution/* (no UI)."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.analysis import EntityRefResponse
from robot_studio.api.schemas.execution_knowledge import (
    EntityStatsListResponse,
    EntityStatsResponse,
    ExecutionHistoryItemResponse,
    ExecutionHistoryListResponse,
    ExecutionKnowledgeSnapshotResponse,
    FlakyListResponse,
    HeatMapListResponse,
    LinkedRunResponse,
    NeverExecutedResponse,
    SlowEntityResponse,
    SlowListResponse,
)
from robot_studio.application.services.execution_knowledge_service import (
    ExecutionKnowledgeValidationError,
)

router = APIRouter(prefix="/analysis/execution", tags=["analysis-execution"])


def _http(exc: ExecutionKnowledgeValidationError) -> HTTPException:
    return HTTPException(status_code=400, detail=str(exc))


@router.get("/snapshot", response_model=ExecutionKnowledgeSnapshotResponse)
async def execution_snapshot(
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionKnowledgeSnapshotResponse:
    try:
        snap = await gateway.execution_knowledge_snapshot(
            UUID(project_id) if project_id else None,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return ExecutionKnowledgeSnapshotResponse.from_model(snap)


@router.post("/link/{run_id}", response_model=LinkedRunResponse | None)
async def link_run(
    run_id: UUID,
    gateway: RestGateway = Depends(get_gateway),
) -> LinkedRunResponse | None:
    try:
        info = await gateway.execution_knowledge_link_run(run_id)
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return LinkedRunResponse.from_model(info) if info else None


@router.get("/keyword-history", response_model=ExecutionHistoryListResponse)
async def keyword_history(
    keyword: str = Query(...),
    limit: int = Query(default=50, ge=1, le=200),
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionHistoryListResponse:
    try:
        items = await gateway.execution_keyword_history(
            keyword,
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return ExecutionHistoryListResponse(
        items=[ExecutionHistoryItemResponse.from_model(i) for i in items],
    )


@router.get("/test-history", response_model=ExecutionHistoryListResponse)
async def test_history(
    test: str = Query(...),
    limit: int = Query(default=50, ge=1, le=200),
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionHistoryListResponse:
    try:
        items = await gateway.execution_test_history(
            test,
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return ExecutionHistoryListResponse(
        items=[ExecutionHistoryItemResponse.from_model(i) for i in items],
    )


@router.get("/last-failures", response_model=ExecutionHistoryListResponse)
async def last_failures(
    limit: int = Query(default=50, ge=1, le=200),
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionHistoryListResponse:
    try:
        items = await gateway.execution_last_failures(
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return ExecutionHistoryListResponse(
        items=[ExecutionHistoryItemResponse.from_model(i) for i in items],
    )


@router.get("/slowest-keywords", response_model=SlowListResponse)
async def slowest_keywords(
    limit: int = Query(default=20, ge=1, le=100),
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> SlowListResponse:
    try:
        items = await gateway.execution_slowest_keywords(
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return SlowListResponse(items=[SlowEntityResponse.from_model(i) for i in items])


@router.get("/slowest-tests", response_model=SlowListResponse)
async def slowest_tests(
    limit: int = Query(default=20, ge=1, le=100),
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> SlowListResponse:
    try:
        items = await gateway.execution_slowest_tests(
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return SlowListResponse(items=[SlowEntityResponse.from_model(i) for i in items])


@router.get("/most-executed-keywords", response_model=EntityStatsListResponse)
async def most_executed_keywords(
    limit: int = Query(default=20, ge=1, le=100),
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> EntityStatsListResponse:
    try:
        items = await gateway.execution_most_executed_keywords(
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return EntityStatsListResponse(items=[EntityStatsResponse.from_model(i) for i in items])


@router.get("/never-executed-keywords", response_model=NeverExecutedResponse)
async def never_executed_keywords(
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> NeverExecutedResponse:
    try:
        items = await gateway.execution_never_executed_keywords(
            UUID(project_id) if project_id else None,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return NeverExecutedResponse(items=[EntityRefResponse.from_model(i) for i in items])


@router.get("/heat-map", response_model=HeatMapListResponse)
async def heat_map(
    limit: int = Query(default=100, ge=1, le=500),
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> HeatMapListResponse:
    try:
        items = await gateway.execution_heat_map(
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return HeatMapListResponse.from_models(items)


@router.get("/flaky-candidates", response_model=FlakyListResponse)
async def flaky_candidates(
    limit: int = Query(default=50, ge=1, le=200),
    project_id: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> FlakyListResponse:
    try:
        items = await gateway.execution_flaky_candidates(
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return FlakyListResponse.from_models(items)
