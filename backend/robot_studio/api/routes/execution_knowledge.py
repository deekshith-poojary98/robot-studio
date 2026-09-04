"""Execution knowledge REST — /analysis/execution/* (no UI)."""

from __future__ import annotations

from typing import Annotated
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
    RunFailuresResponse,
    RunTestFailureResponse,
    SlowEntityResponse,
    SlowListResponse,
)
from robot_studio.application.services.execution_knowledge_service import (
    ExecutionKnowledgeValidationError,
)

router = APIRouter(prefix="/analysis/execution", tags=["analysis-execution"])
GatewayDep = Annotated[RestGateway, Depends(get_gateway)]


def _http(exc: ExecutionKnowledgeValidationError) -> HTTPException:
    return HTTPException(status_code=400, detail=str(exc))


@router.get("/snapshot", response_model=ExecutionKnowledgeSnapshotResponse)
async def execution_snapshot(
    gateway: GatewayDep,
    project_id: Annotated[str | None, Query()] = None,
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
    gateway: GatewayDep,
) -> LinkedRunResponse | None:
    try:
        info = await gateway.execution_knowledge_link_run(run_id)
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return LinkedRunResponse.from_model(info) if info else None


@router.get("/keyword-history", response_model=ExecutionHistoryListResponse)
async def keyword_history(
    gateway: GatewayDep,
    keyword: Annotated[str, Query()],
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    project_id: Annotated[str | None, Query()] = None,
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
    gateway: GatewayDep,
    test: Annotated[str, Query()],
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    project_id: Annotated[str | None, Query()] = None,
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
    gateway: GatewayDep,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    project_id: Annotated[str | None, Query()] = None,
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


@router.get("/run-failures", response_model=RunFailuresResponse)
async def run_failures(
    gateway: GatewayDep,
    run_id: Annotated[UUID, Query()],
) -> RunFailuresResponse:
    """Failed tests for one run — Jump to Source / re-run consumers share this."""
    try:
        items = await gateway.execution_run_failures(run_id)
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return RunFailuresResponse(
        run_id=str(run_id),
        items=[RunTestFailureResponse.from_model(i) for i in items],
    )


@router.get("/slowest-keywords", response_model=SlowListResponse)
async def slowest_keywords(
    gateway: GatewayDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    project_id: Annotated[str | None, Query()] = None,
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
    gateway: GatewayDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    project_id: Annotated[str | None, Query()] = None,
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
    gateway: GatewayDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    project_id: Annotated[str | None, Query()] = None,
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
    gateway: GatewayDep,
    project_id: Annotated[str | None, Query()] = None,
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
    gateway: GatewayDep,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
    project_id: Annotated[str | None, Query()] = None,
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
    gateway: GatewayDep,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    project_id: Annotated[str | None, Query()] = None,
) -> FlakyListResponse:
    try:
        items = await gateway.execution_flaky_candidates(
            UUID(project_id) if project_id else None,
            limit=limit,
        )
    except ExecutionKnowledgeValidationError as exc:
        raise _http(exc) from exc
    return FlakyListResponse.from_models(items)
