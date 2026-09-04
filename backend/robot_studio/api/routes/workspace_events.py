"""WebSocket fan-out for live workspace filesystem / domain events."""

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from robot_studio.core.container import container

router = APIRouter(prefix="/workspace", tags=["workspace"])


@router.websocket("/events")
async def workspace_events(websocket: WebSocket) -> None:
    await websocket.accept()
    service = container.workspace_event_service
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
