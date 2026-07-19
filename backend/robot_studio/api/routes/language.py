from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.index import (
    HoverResponse,
    ReferenceListResponse,
    ReferenceResponse,
    SymbolResponse,
    to_symbol_response,
)
from robot_studio.application.services.language_service import LanguageValidationError

router = APIRouter(prefix="/language", tags=["language"])


@router.get("/definition", response_model=SymbolResponse | None)
async def language_definition(
    name: str | None = Query(default=None),
    symbol_id: str | None = Query(default=None),
    kind: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> SymbolResponse | None:
    try:
        result = await gateway.language_definition(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if result is None:
        return None
    return to_symbol_response(result)


@router.get("/references", response_model=ReferenceListResponse)
async def language_references(
    name: str | None = Query(default=None),
    symbol_id: str | None = Query(default=None),
    kind: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> ReferenceListResponse:
    try:
        refs = await gateway.language_references(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return ReferenceListResponse(
        references=[
            ReferenceResponse(
                symbol_id=item.get("symbol_id") or "",
                name=item["name"],
                file_path=item["file_path"],
                line=int(item.get("line") or 1),
                project_id=item.get("project_id"),
                context=item.get("context") or "",
            )
            for item in refs
        ],
    )


@router.get("/hover", response_model=HoverResponse | None)
async def language_hover(
    name: str | None = Query(default=None),
    symbol_id: str | None = Query(default=None),
    kind: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> HoverResponse | None:
    try:
        result = await gateway.language_hover(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if result is None:
        return None
    return HoverResponse(
        name=result["name"],
        kind=result["kind"],
        file_path=result["file_path"],
        line=int(result.get("line") or 1),
        documentation=result.get("documentation") or "",
        detail=result.get("detail") or "",
        id=result.get("id") or "",
    )
