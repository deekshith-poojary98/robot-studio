from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.execution import (
    ExecutionHistoryResponse,
    ExecutionResponse,
    ExecutionStatusResponse,
    RunFileRequest,
    to_execution_response,
)
from robot_studio.application.services.execution_service import ExecutionValidationError
from robot_studio.core.container import container
from robot_studio.domain.models import ExecutionStatus

router = APIRouter(prefix="/execution", tags=["execution"])


@router.post("/run", response_model=ExecutionResponse)
async def run_file(
    request: RunFileRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    try:
        run = await gateway.run_file(file_path=request.file)
    except ExecutionValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/run-project", response_model=ExecutionResponse)
async def run_project(
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    try:
        run = await gateway.run_project()
    except ExecutionValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_execution_response(run)


@router.post("/stop", response_model=ExecutionResponse)
async def stop_execution(
    gateway: RestGateway = Depends(get_gateway),
) -> ExecutionResponse:
    try:
        run = await gateway.stop_execution()
    except ExecutionValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if run is None:
        raise HTTPException(status_code=400, detail="No active execution")
    return to_execution_response(run)


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
