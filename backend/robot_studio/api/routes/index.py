from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.index import (
    IndexStatusResponse,
    SearchResponse,
    to_index_status,
    to_symbol_response,
)
from robot_studio.application.services.index_service import IndexValidationError
from robot_studio.domain.interfaces.indexing import SymbolKind

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


search_router = APIRouter(prefix="/search", tags=["search"])


@search_router.get("", response_model=SearchResponse)
async def search_symbols(
    q: str = Query(default=""),
    kind: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    gateway: RestGateway = Depends(get_gateway),
) -> SearchResponse:
    symbol_kind = None
    if kind:
        try:
            symbol_kind = SymbolKind(kind)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=f"Unknown kind: {kind}") from exc
    try:
        results = await gateway.search_symbols(query=q, kind=symbol_kind, limit=limit)
    except IndexValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return SearchResponse(results=[to_symbol_response(item) for item in results])
