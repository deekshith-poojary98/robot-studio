"""Test Explorer REST routes."""

from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.execution import ExecutionResponse, to_execution_response
from robot_studio.api.schemas.test_explorer import (
    RunSelectedRequest,
    RunSuiteRequest,
    RunTagRequest,
    RunTestRequest,
    TestFileResponse,
    TestTreeResponse,
    to_test_node,
)
from robot_studio.application.services.execution_service import ExecutionValidationError
from robot_studio.application.services.test_explorer_service import (
    TestExplorerValidationError,
)

router = APIRouter(prefix="/tests", tags=["tests"])


@router.get("/tree", response_model=TestTreeResponse)
async def get_test_tree(
    q: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> TestTreeResponse:
    try:
        tree = await gateway.get_test_tree(query=q)
    except TestExplorerValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return TestTreeResponse(tree=to_test_node(tree))


@router.get("/file", response_model=TestFileResponse)
async def get_tests_for_file(
    path: str = Query(min_length=1),
    gateway: RestGateway = Depends(get_gateway),
) -> TestFileResponse:
    try:
        nodes = await gateway.get_tests_for_file(path=path)
    except TestExplorerValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return TestFileResponse(nodes=[to_test_node(item) for item in nodes])


@router.post("/run", response_model=ExecutionResponse)
async def run_test(
    request: RunTestRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    try:
        run = await gateway.run_test(file=request.file, name=request.name)
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/run-suite", response_model=ExecutionResponse)
async def run_suite(
    request: RunSuiteRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    try:
        run = await gateway.run_test_suite(file=request.file)
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/run-tag", response_model=ExecutionResponse)
async def run_tag(
    request: RunTagRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    try:
        run = await gateway.run_tests_by_tag(tag=request.tag)
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/run-failed", response_model=ExecutionResponse)
async def run_failed(
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    try:
        run = await gateway.run_failed_tests()
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/run-selected", response_model=ExecutionResponse)
async def run_selected(
    request: RunSelectedRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    try:
        run = await gateway.run_selected_tests(
            tests=[item.model_dump() for item in request.tests],
        )
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)
