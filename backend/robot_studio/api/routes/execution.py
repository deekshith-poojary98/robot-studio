from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.execution import (
    ExecutionHistoryResponse,
    ExecutionResponse,
    ExecutionStatusResponse,
    RunFileRequest,
    RunProjectRequest,
    to_execution_response,
)
from robot_studio.application.services.execution_service import ExecutionValidationError
from robot_studio.application.services.test_explorer_service import (
    TestExplorerValidationError,
)
from robot_studio.core.container import container
from robot_studio.domain.models import ExecutionStatus

router = APIRouter(prefix="/execution", tags=["execution"])


def _http_run_error(exc: Exception) -> HTTPException:
    if isinstance(exc, TestExplorerValidationError) and exc.code == "large_run_confirmation_required":
        return HTTPException(
            status_code=409,
            detail={
                "code": exc.code,
                "message": str(exc),
                "count": exc.count,
                "threshold": exc.threshold,
            },
        )
    if isinstance(exc, (ExecutionValidationError, TestExplorerValidationError)):
        return HTTPException(status_code=400, detail=str(exc))
    return HTTPException(status_code=400, detail=str(exc))


@router.post("/run", response_model=ExecutionResponse)
async def run_file(
    request: RunFileRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    try:
        run = await gateway.run_file(file_path=request.file)
    except (ExecutionValidationError, TestExplorerValidationError) as exc:
        raise _http_run_error(exc) from exc
    return to_execution_response(run)


@router.post("/run-project", response_model=ExecutionResponse)
async def run_project(
    request: RunProjectRequest | None = None,
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    body = request or RunProjectRequest()
    try:
        run = await gateway.run_project(confirm=body.confirm)
    except (ExecutionValidationError, TestExplorerValidationError) as exc:
        raise _http_run_error(exc) from exc
    return to_execution_response(run)


@router.post("/stop", response_model=ExecutionStatusResponse)
async def stop_execution(
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionStatusResponse:
    try:
        run = await gateway.stop_execution()
    except ExecutionValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if run is None:
        return ExecutionStatusResponse(status=ExecutionStatus.IDLE, run=None)
    return ExecutionStatusResponse(
        status=run.status,
        run=to_execution_response(run),
    )


@router.get("/history", response_model=ExecutionHistoryResponse)
async def execution_history(
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionHistoryResponse:
    try:
        runs = await gateway.list_execution_history()
    except ExecutionValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return ExecutionHistoryResponse(
        runs=[to_execution_response(item) for item in runs],
    )


@router.get("/status", response_model=ExecutionStatusResponse)
async def execution_status(
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionStatusResponse:
    run = await gateway.get_execution_status()
    if run is None:
        return ExecutionStatusResponse(status=ExecutionStatus.IDLE, run=None)
    return ExecutionStatusResponse(
        status=run.status,
        run=to_execution_response(run),
    )


@router.websocket("/stream")
async def execution_stream(websocket: WebSocket) -> None:
    await websocket.accept()
    service = container.execution_service
    if service is None:
        await websocket.close(code=1011)
        return

    queue = await service.subscribe()
    try:
        await websocket.send_json({"type": "connected"})
        while True:
            message = await queue.get()
            await websocket.send_json(message)
    except WebSocketDisconnect:
        pass
    finally:
        await service.unsubscribe(queue)
