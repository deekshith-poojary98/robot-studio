from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.index import (
    HoverResponse,
    ReferenceListResponse,
    ReferenceResponse,
    SearchResponse,
    SymbolResponse,
    to_symbol_response,
)
from robot_studio.api.schemas.language import (
    CompletionListResponse,
    CompletionRequest,
    CompletionUsageRequest,
    DiagnosticListResponse,
    DiagnosticsRequest,
    FormatRequest,
    FormatResponse,
    SignatureHelpRequest,
    SignatureHelpResponse,
)
from robot_studio.application.services.language_service import LanguageValidationError

router = APIRouter(prefix="/language", tags=["language"])


@router.get("/definition", response_model=SymbolResponse | None)
async def language_definition(
    name: str | None = Query(default=None),
    symbol_id: str | None = Query(default=None),
    kind: str | None = Query(default=None),
    file: str | None = Query(default=None),
    line: int | None = Query(default=None),
    column: int | None = Query(default=None),
    content: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> SymbolResponse | None:
    try:
        result = await gateway.language_definition(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
            file_path=file,
            line=line,
            column=column,
            content=content,
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
    file: str | None = Query(default=None),
    line: int | None = Query(default=None),
    column: int | None = Query(default=None),
    content: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> ReferenceListResponse:
    try:
        refs = await gateway.language_references(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
            file_path=file,
            line=line,
            column=column,
            content=content,
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
    file: str | None = Query(default=None),
    line: int | None = Query(default=None),
    column: int | None = Query(default=None),
    content: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> HoverResponse | None:
    try:
        result = await gateway.language_hover(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
            file_path=file,
            line=line,
            column=column,
            content=content,
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


@router.post("/completion", response_model=CompletionListResponse)
async def language_completion(
    body: CompletionRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> CompletionListResponse:
    try:
        items = await gateway.language_completion(
            file_path=body.file_path,
            line=body.line,
            column=body.column,
            content=body.content,
            query=body.query,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return CompletionListResponse(
        items=[
            {
                "label": item["label"],
                "kind": item["kind"],
                "detail": item.get("detail") or "",
                "documentation": item.get("documentation") or "",
                "insert_text": item.get("insert_text") or item["label"],
                "provider": item.get("provider") or "",
            }
            for item in items
        ],
    )


@router.post("/completion/usage")
async def language_completion_usage(
    body: CompletionUsageRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> dict:
    try:
        await gateway.language_completion_usage(
            label=body.label,
            kind=body.kind,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"ok": True}


@router.post("/diagnostics", response_model=DiagnosticListResponse)
async def language_diagnostics(
    body: DiagnosticsRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> DiagnosticListResponse:
    try:
        diagnostics = await gateway.language_diagnostics(
            file_path=body.file_path,
            content=body.content,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return DiagnosticListResponse(
        diagnostics=[
            {
                "severity": item.get("severity") or "error",
                "file_path": item.get("file_path") or body.file_path,
                "line": int(item.get("line") or 1),
                "column": int(item.get("column") or 1),
                "message": str(item.get("message") or ""),
                "source": item.get("source") or "robot",
                "code": item.get("code"),
                "inspection_id": item.get("inspection_id"),
            }
            for item in diagnostics
        ],
    )


@router.post("/format", response_model=FormatResponse)
async def language_format(
    body: FormatRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> FormatResponse:
    try:
        formatted = await gateway.language_format(
            file_path=body.file_path,
            content=body.content,
            start_line=body.start_line,
            end_line=body.end_line,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FormatResponse(content=formatted)


@router.post("/signature-help", response_model=SignatureHelpResponse | None)
async def language_signature_help(
    body: SignatureHelpRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> SignatureHelpResponse | None:
    try:
        result = await gateway.language_signature_help(
            file_path=body.file_path,
            line=body.line,
            column=body.column,
            content=body.content,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if result is None:
        return None
    return SignatureHelpResponse(
        keyword=result["keyword"],
        documentation=result.get("documentation") or "",
        detail=result.get("detail") or "",
        active_parameter=int(result.get("active_parameter") or 0),
        source_type=result.get("source_type") or "",
        library_name=result.get("library_name") or "",
        deprecated=bool(result.get("deprecated") or False),
        parameters=[
            {
                "label": param.get("label") or "",
                "name": param.get("name") or "",
                "documentation": param.get("documentation") or "",
                "default": param.get("default"),
                "required": bool(param.get("required") or False),
                "kind": param.get("kind") or "",
            }
            for param in result.get("parameters") or []
        ],
    )


@router.get("/document-symbols", response_model=SearchResponse)
async def document_symbols(
    file: str = Query(min_length=1),
    gateway: RestGateway = Depends(get_gateway),
) -> SearchResponse:
    try:
        results = await gateway.document_symbols(file)
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return SearchResponse(results=[to_symbol_response(item) for item in results])


@router.get("/workspace-symbols", response_model=SearchResponse)
async def workspace_symbols(
    q: str = Query(default=""),
    limit: int = Query(default=200, ge=1, le=500),
    gateway: RestGateway = Depends(get_gateway),
) -> SearchResponse:
    try:
        results = await gateway.workspace_symbols(query=q, limit=limit)
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return SearchResponse(results=[to_symbol_response(item) for item in results])
