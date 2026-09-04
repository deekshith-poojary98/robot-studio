"""Test Explorer REST routes."""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.execution import ExecutionResponse, to_execution_response
from robot_studio.api.schemas.test_explorer import (
    RunFailedRequest,
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
GatewayDep = Annotated[RestGateway, Depends(get_gateway)]


@router.get("/tree", response_model=TestTreeResponse)
async def get_test_tree(
    gateway: GatewayDep,
    q: Annotated[str | None, Query()] = None,
    lazy: Annotated[bool, Query()] = True,
) -> TestTreeResponse:
    try:
        tree = await gateway.get_test_tree(query=q, lazy=lazy)
    except TestExplorerValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return TestTreeResponse(tree=to_test_node(tree))


@router.get("/count")
async def count_tests(
    gateway: GatewayDep,
    tag: Annotated[str | None, Query()] = None,
    project_wide: Annotated[bool, Query()] = False,
) -> dict:
    try:
        total = await gateway.count_tests(tag=tag, project_wide=project_wide)
    except TestExplorerValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"count": total}

@router.get("/file", response_model=TestFileResponse)
async def get_tests_for_file(
    gateway: GatewayDep,
    path: Annotated[str, Query(min_length=1)],
) -> TestFileResponse:
    try:
        nodes = await gateway.get_tests_for_file(path=path)
    except TestExplorerValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return TestFileResponse(nodes=[to_test_node(item) for item in nodes])


@router.post("/run", response_model=ExecutionResponse)
async def run_test(
    request: RunTestRequest,
    gateway: GatewayDep,
) -> ExecutionResponse:
    try:
        run = await gateway.run_test(
            file=request.file,
            name=request.name,
            configuration_id=request.configuration_id,
        )
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/run-suite", response_model=ExecutionResponse)
async def run_suite(
    request: RunSuiteRequest,
    gateway: GatewayDep,
) -> ExecutionResponse:
    try:
        run = await gateway.run_test_suite(
            file=request.file,
            confirm=request.confirm,
            configuration_id=request.configuration_id,
        )
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        if (
            isinstance(exc, TestExplorerValidationError)
            and exc.code == "large_run_confirmation_required"
        ):
            raise HTTPException(
                status_code=409,
                detail={
                    "code": exc.code,
                    "message": str(exc),
                    "count": exc.count,
                    "threshold": exc.threshold,
                },
            ) from exc
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/run-tag", response_model=ExecutionResponse)
async def run_tag(
    request: RunTagRequest,
    gateway: GatewayDep,
) -> ExecutionResponse:
    try:
        run = await gateway.run_tests_by_tag(
            tag=request.tag,
            confirm=request.confirm,
            configuration_id=request.configuration_id,
        )
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        if (
            isinstance(exc, TestExplorerValidationError)
            and exc.code == "large_run_confirmation_required"
        ):
            raise HTTPException(
                status_code=409,
                detail={
                    "code": exc.code,
                    "message": str(exc),
                    "count": exc.count,
                    "threshold": exc.threshold,
                },
            ) from exc
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/run-failed", response_model=ExecutionResponse)
async def run_failed(
    gateway: GatewayDep,
    request: RunFailedRequest | None = None,
) -> ExecutionResponse:
    body = request or RunFailedRequest()
    try:
        run = await gateway.run_failed_tests(configuration_id=body.configuration_id)
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/run-selected", response_model=ExecutionResponse)
async def run_selected(
    request: RunSelectedRequest,
    gateway: GatewayDep,
) -> ExecutionResponse:
    try:
        run = await gateway.run_selected_tests(
            tests=[item.model_dump() for item in request.tests],
            configuration_id=request.configuration_id,
        )
    except (TestExplorerValidationError, ExecutionValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)
