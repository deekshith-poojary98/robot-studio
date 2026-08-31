from pydantic import BaseModel, Field


class CompletionItemResponse(BaseModel):
    label: str
    kind: str
    detail: str = ""
    documentation: str = ""
    insert_text: str = ""
    provider: str = ""


class CompletionListResponse(BaseModel):
    items: list[CompletionItemResponse] = Field(default_factory=list)


class CompletionRequest(BaseModel):
    file_path: str
    line: int = 1
    column: int = 1
    content: str = ""
    query: str = ""


class CompletionUsageRequest(BaseModel):
    label: str
    kind: str = ""


class QuickFixHintResponse(BaseModel):
    """Action the Problems panel can apply without a second round-trip."""

    kind: str
    title: str
    package: str | None = None
    library: str | None = None


class DiagnosticResponse(BaseModel):
    severity: str
    file_path: str
    line: int = 1
    column: int = 1
    message: str
    source: str = "robot"
    code: str | None = None
    inspection_id: str | None = None
    quick_fix: QuickFixHintResponse | None = None


class DiagnosticListResponse(BaseModel):
    diagnostics: list[DiagnosticResponse] = Field(default_factory=list)


class DiagnosticsRequest(BaseModel):
    file_path: str
    content: str = ""


class FormatRequest(BaseModel):
    file_path: str
    content: str = ""
    start_line: int | None = None
    end_line: int | None = None


class FormatResponse(BaseModel):
    content: str


class RenameRequest(BaseModel):
    file_path: str
    line: int = 1
    column: int = 1
    content: str = ""
    new_name: str


class RenameFileEdit(BaseModel):
    file_path: str
    content: str


class RenameResponse(BaseModel):
    """Edits are returned, not applied — the client owns dirty buffers."""

    error: str = ""
    files: list[RenameFileEdit] = Field(default_factory=list)


class SignatureParameterResponse(BaseModel):
    label: str
    name: str = ""
    documentation: str = ""
    default: str | None = None
    required: bool = False
    kind: str = ""


class SignatureHelpResponse(BaseModel):
    keyword: str
    documentation: str = ""
    detail: str = ""
    active_parameter: int = 0
    parameters: list[SignatureParameterResponse] = Field(default_factory=list)
    source_type: str = ""
    library_name: str = ""
    deprecated: bool = False


class SignatureHelpRequest(BaseModel):
    file_path: str
    line: int = 1
    column: int = 1
    content: str = ""
    # When true, only resolve the keyword cell under the pointer (mouse hover).
    # Caret-driven signature help while typing arguments leaves this false.
    hover: bool = False


class HoverRequest(BaseModel):
    """Buffer-backed hover. GET /hover is name-only and cannot carry a file."""

    file_path: str = ""
    line: int = 1
    column: int = 1
    content: str = ""
    name: str | None = None
    symbol_id: str | None = None
    kind: str | None = None


class LibraryKeywordResponse(BaseModel):
    name: str
    qualified_name: str = ""
    source_type: str = ""
    library_name: str = ""
    documentation: str = ""
    doc_format: str = ""
    parameters: list[SignatureParameterResponse] = Field(default_factory=list)
    source_path: str = ""
    source_line: int | None = None
    deprecated: bool = False
    tags: list[str] = Field(default_factory=list)
    detail: str = ""


class LibrarySummaryResponse(BaseModel):
    name: str
    version: str = ""
    documentation: str = ""
    doc_format: str = ""
    source_type: str = ""
    source_path: str = ""
    builtin: bool = False
    keyword_count: int = 0
    last_updated: str | None = None


class LibraryListResponse(BaseModel):
    libraries: list[LibrarySummaryResponse] = Field(default_factory=list)


class LibraryDetailResponse(LibrarySummaryResponse):
    keywords: list[LibraryKeywordResponse] = Field(default_factory=list)


class DocumentAnalysisRequest(BaseModel):
    file_path: str
    content: str = ""


class DocumentSymbolNodeResponse(BaseModel):
    id: str = ""
    name: str
    kind: str
    line: int = 1
    end_line: int = 1
    column: int = 1
    detail: str = ""
    documentation: str = ""
    children: list["DocumentSymbolNodeResponse"] = Field(default_factory=list)


class FoldingRangeResponse(BaseModel):
    start_line: int
    end_line: int


class DocumentAnalysisResponse(BaseModel):
    file_path: str
    content_hash: str = ""
    root: DocumentSymbolNodeResponse
    folding_ranges: list[FoldingRangeResponse] = Field(default_factory=list)


def to_document_symbol_node(raw: dict) -> DocumentSymbolNodeResponse:
    children = [
        to_document_symbol_node(child)
        for child in (raw.get("children") or [])
        if isinstance(child, dict)
    ]
    return DocumentSymbolNodeResponse(
        id=str(raw.get("id") or ""),
        name=str(raw.get("name") or ""),
        kind=str(raw.get("kind") or "symbol"),
        line=int(raw.get("line") or 1),
        end_line=int(raw.get("end_line") or raw.get("line") or 1),
        column=int(raw.get("column") or 1),
        detail=str(raw.get("detail") or ""),
        documentation=str(raw.get("documentation") or ""),
        children=children,
    )


def to_document_analysis_response(raw: dict) -> DocumentAnalysisResponse:
    root_raw = raw.get("root") if isinstance(raw.get("root"), dict) else {}
    folding = [
        FoldingRangeResponse(
            start_line=int(item.get("start_line") or 0),
            end_line=int(item.get("end_line") or 0),
        )
        for item in (raw.get("folding_ranges") or [])
        if isinstance(item, dict)
    ]
    return DocumentAnalysisResponse(
        file_path=str(raw.get("file_path") or ""),
        content_hash=str(raw.get("content_hash") or ""),
        root=to_document_symbol_node(root_raw or {}),
        folding_ranges=folding,
    )
