from typing import Annotated

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
    DefinitionRequest,
    DiagnosticListResponse,
    DiagnosticsRequest,
    DocumentAnalysisRequest,
    DocumentAnalysisResponse,
    FormatRequest,
    FormatResponse,
    HoverRequest,
    LibraryDetailResponse,
    LibraryListResponse,
    ReferencesRequest,
    RenameFileEdit,
    RenameRequest,
    RenameResponse,
    SignatureHelpRequest,
    SignatureHelpResponse,
    to_document_analysis_response,
)
from robot_studio.application.services.language_service import LanguageValidationError

router = APIRouter(prefix="/language", tags=["language"])
GatewayDep = Annotated[RestGateway, Depends(get_gateway)]


async def _definition_result(
    gateway: RestGateway,
    *,
    name: str | None,
    symbol_id: str | None,
    kind: str | None,
    file_path: str | None,
    line: int | None,
    column: int | None,
    content: str | None,
) -> SymbolResponse | None:
    try:
        result = await gateway.language_definition(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
            file_path=file_path,
            line=line,
            column=column,
            content=content,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if result is None:
        return None
    return to_symbol_response(result)


@router.get("/definition", response_model=SymbolResponse | None)
async def language_definition(
    gateway: GatewayDep,
    name: Annotated[str | None, Query()] = None,
    symbol_id: Annotated[str | None, Query()] = None,
    kind: Annotated[str | None, Query()] = None,
    file: Annotated[str | None, Query()] = None,
    line: Annotated[int | None, Query()] = None,
    column: Annotated[int | None, Query()] = None,
) -> SymbolResponse | None:
    """Name/index lookup. Send a live buffer with POST — GET cannot carry a file."""
    return await _definition_result(
        gateway,
        name=name,
        symbol_id=symbol_id,
        kind=kind,
        file_path=file,
        line=line,
        column=column,
        content=None,
    )


@router.post("/definition", response_model=SymbolResponse | None)
async def language_definition_at(
    body: DefinitionRequest,
    gateway: GatewayDep,
) -> SymbolResponse | None:
    """Canonical go-to-definition (index and/or live buffer)."""
    return await _definition_result(
        gateway,
        name=body.name,
        symbol_id=body.symbol_id,
        kind=body.kind,
        file_path=body.file_path or None,
        line=body.line,
        column=body.column,
        content=body.content or None,
    )


async def _references_result(
    gateway: RestGateway,
    *,
    name: str | None,
    symbol_id: str | None,
    kind: str | None,
    file_path: str | None,
    line: int | None,
    column: int | None,
    content: str | None,
) -> ReferenceListResponse:
    try:
        refs = await gateway.language_references(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
            file_path=file_path,
            line=line,
            column=column,
            content=content,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _references_response(refs)


@router.get("/references", response_model=ReferenceListResponse)
async def language_references(
    gateway: GatewayDep,
    name: Annotated[str | None, Query()] = None,
    symbol_id: Annotated[str | None, Query()] = None,
    kind: Annotated[str | None, Query()] = None,
    file: Annotated[str | None, Query()] = None,
    line: Annotated[int | None, Query()] = None,
    column: Annotated[int | None, Query()] = None,
) -> ReferenceListResponse:
    """Name/index lookup. Send a live buffer with POST — GET cannot carry a file."""
    return await _references_result(
        gateway,
        name=name,
        symbol_id=symbol_id,
        kind=kind,
        file_path=file,
        line=line,
        column=column,
        content=None,
    )


@router.post("/references", response_model=ReferenceListResponse)
async def language_references_at(
    body: ReferencesRequest,
    gateway: GatewayDep,
) -> ReferenceListResponse:
    """Canonical find-references (index and/or live buffer)."""
    return await _references_result(
        gateway,
        name=body.name,
        symbol_id=body.symbol_id,
        kind=body.kind,
        file_path=body.file_path or None,
        line=body.line,
        column=body.column,
        content=body.content or None,
    )


def _references_response(refs: list[dict]) -> ReferenceListResponse:
    return ReferenceListResponse(
        references=[
            ReferenceResponse(
                symbol_id=item.get("symbol_id") or "",
                name=item["name"],
                file_path=item["file_path"],
                line=int(item.get("line") or 1),
                column=int(item.get("column") or 1),
                project_id=item.get("project_id"),
                context=item.get("context") or "",
            )
            for item in refs
        ],
    )


async def _hover_result(
    gateway: RestGateway,
    *,
    name: str | None,
    symbol_id: str | None,
    kind: str | None,
    file_path: str | None,
    line: int | None,
    column: int | None,
    content: str | None,
) -> HoverResponse | None:
    try:
        result = await gateway.language_hover(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
            file_path=file_path,
            line=line,
            column=column,
            content=content,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if result is None:
        return None
    return _hover_response(result)


@router.get("/hover", response_model=HoverResponse | None)
async def language_hover(
    gateway: GatewayDep,
    name: Annotated[str | None, Query()] = None,
    symbol_id: Annotated[str | None, Query()] = None,
    kind: Annotated[str | None, Query()] = None,
    file: Annotated[str | None, Query()] = None,
    line: Annotated[int | None, Query()] = None,
    column: Annotated[int | None, Query()] = None,
) -> HoverResponse | None:
    """Name/index lookup. Send a live buffer with POST — GET cannot carry a file."""
    return await _hover_result(
        gateway,
        name=name,
        symbol_id=symbol_id,
        kind=kind,
        file_path=file,
        line=line,
        column=column,
        content=None,
    )


@router.post("/hover", response_model=HoverResponse | None)
async def language_hover_at(
    body: HoverRequest,
    gateway: GatewayDep,
) -> HoverResponse | None:
    """Canonical hover (index and/or live buffer)."""
    return await _hover_result(
        gateway,
        name=body.name,
        symbol_id=body.symbol_id,
        kind=body.kind,
        file_path=body.file_path or None,
        line=body.line,
        column=body.column,
        content=body.content or None,
    )


def _hover_response(result: dict) -> HoverResponse:
    return HoverResponse(
        name=result["name"],
        kind=result["kind"],
        file_path=result["file_path"],
        line=int(result.get("line") or 1),
        documentation=result.get("documentation") or "",
        detail=result.get("detail") or "",
        detail_kind=str(result.get("detail_kind") or ""),
        id=result.get("id") or "",
    )


@router.post("/rename", response_model=RenameResponse)
async def language_rename(
    body: RenameRequest,
    gateway: GatewayDep,
) -> RenameResponse:
    try:
        result = await gateway.language_rename(
            file_path=body.file_path,
            line=body.line,
            column=body.column,
            content=body.content,
            new_name=body.new_name,
        )
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return RenameResponse(
        error=str(result.get("error") or ""),
        files=[
            RenameFileEdit(
                file_path=str(item.get("file_path") or ""),
                content=str(item.get("content") or ""),
            )
            for item in (result.get("files") or [])
        ],
    )


@router.post("/completion", response_model=CompletionListResponse)
async def language_completion(
    body: CompletionRequest,
    gateway: GatewayDep,
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
    gateway: GatewayDep,
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
    gateway: GatewayDep,
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
                "quick_fix": item.get("quick_fix"),
            }
            for item in diagnostics
        ],
    )


@router.post("/format", response_model=FormatResponse)
async def language_format(
    body: FormatRequest,
    gateway: GatewayDep,
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
    gateway: GatewayDep,
) -> SignatureHelpResponse | None:
    try:
        result = await gateway.language_signature_help(
            file_path=body.file_path,
            line=body.line,
            column=body.column,
            content=body.content,
            hover=body.hover,
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


@router.get("/libraries", response_model=LibraryListResponse)
async def language_libraries(
    gateway: GatewayDep,
) -> LibraryListResponse:
    try:
        items = await gateway.language_libraries()
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return LibraryListResponse(libraries=items)


@router.get("/libraries/{name}", response_model=LibraryDetailResponse | None)
async def language_library_detail(
    name: str,
    gateway: GatewayDep,
) -> LibraryDetailResponse | None:
    try:
        result = await gateway.language_library(name)
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if result is None:
        raise HTTPException(status_code=404, detail=f"Library '{name}' not found")
    keywords = []
    for kw in result.get("keywords") or []:
        keywords.append(
            {
                "name": kw.get("name") or "",
                "qualified_name": kw.get("qualified_name") or "",
                "source_type": kw.get("source_type") or "",
                "library_name": kw.get("library_name") or "",
                "documentation": kw.get("documentation") or "",
                "doc_format": kw.get("doc_format") or "",
                "parameters": [
                    {
                        "label": p.get("label") or "",
                        "name": p.get("name") or "",
                        "documentation": p.get("documentation") or "",
                        "default": p.get("default"),
                        "required": bool(p.get("required") or False),
                        "kind": p.get("kind") or "",
                    }
                    for p in (kw.get("parameters") or [])
                ],
                "source_path": kw.get("source_path") or "",
                "source_line": kw.get("source_line"),
                "deprecated": bool(kw.get("deprecated") or False),
                "tags": list(kw.get("tags") or []),
                "detail": kw.get("detail") or "",
            },
        )
    return LibraryDetailResponse(
        name=result.get("name") or name,
        version=result.get("version") or "",
        documentation=result.get("documentation") or "",
        doc_format=result.get("doc_format") or "",
        source_type=result.get("source_type") or "",
        source_path=result.get("source_path") or "",
        builtin=bool(result.get("builtin") or False),
        keyword_count=int(result.get("keyword_count") or len(keywords)),
        last_updated=result.get("last_updated"),
        keywords=keywords,
    )


@router.get("/document-symbols", response_model=SearchResponse)
async def document_symbols(
    gateway: GatewayDep,
    file: Annotated[str, Query(min_length=1)],
) -> SearchResponse:
    try:
        results = await gateway.document_symbols(file)
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return SearchResponse(results=[to_symbol_response(item) for item in results])


@router.post("/document-analysis", response_model=DocumentAnalysisResponse)
async def document_analysis(
    body: DocumentAnalysisRequest,
    gateway: GatewayDep,
) -> DocumentAnalysisResponse:
    try:
        result = await gateway.analyze_document(body.file_path, body.content)
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_document_analysis_response(result)


@router.get("/workspace-symbols", response_model=SearchResponse)
async def workspace_symbols(
    gateway: GatewayDep,
    q: Annotated[str, Query()] = "",
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
) -> SearchResponse:
    try:
        results = await gateway.workspace_symbols(query=q, limit=limit)
    except LanguageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return SearchResponse(results=[to_symbol_response(item) for item in results])
