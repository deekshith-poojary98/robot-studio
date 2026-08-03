"""Search routes — symbols and content are separate providers."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.index import SearchResponse, to_symbol_response
from robot_studio.api.schemas.search import ContentSearchResponse, to_content_search
from robot_studio.application.services.content_search_service import (
    ContentSearchValidationError,
)
from robot_studio.application.services.index_service import IndexValidationError
from robot_studio.domain.interfaces.indexing import SymbolKind

router = APIRouter(prefix="/search", tags=["search"])


@router.get("/symbols", response_model=SearchResponse)
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


@router.get("/content", response_model=ContentSearchResponse)
async def search_content(
    q: str = Query(default=""),
    limit: int = Query(default=500, ge=1, le=2000),
    context_lines: int = Query(default=1, ge=0, le=5),
    gateway: RestGateway = Depends(get_gateway),
) -> ContentSearchResponse:
    try:
        result = await gateway.search_content(
            query=q,
            limit=limit,
            context_lines=context_lines,
        )
    except ContentSearchValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_content_search(result)
