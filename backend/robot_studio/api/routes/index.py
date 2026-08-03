from fastapi import APIRouter, Depends, HTTPException

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.index import (
    IndexStatusResponse,
    to_index_status,
)
from robot_studio.application.services.index_service import IndexValidationError

router = APIRouter(prefix="/index", tags=["index"])


@router.post("/rebuild", response_model=IndexStatusResponse)
async def rebuild_index(
    gateway: RestGateway = Depends(get_gateway),
) -> IndexStatusResponse:
    try:
        status = await gateway.rebuild_index()
    except IndexValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_index_status(status)


@router.get("/status", response_model=IndexStatusResponse)
async def index_status(
    gateway: RestGateway = Depends(get_gateway),
) -> IndexStatusResponse:
    try:
        status = await gateway.get_index_status()
    except IndexValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_index_status(status)
