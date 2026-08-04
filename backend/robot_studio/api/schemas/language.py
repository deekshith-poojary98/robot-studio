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


class DiagnosticResponse(BaseModel):
    severity: str
    file_path: str
    line: int = 1
    column: int = 1
    message: str
    source: str = "robot"
    code: str | None = None
    inspection_id: str | None = None


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


class LibraryKeywordResponse(BaseModel):
    name: str
    qualified_name: str = ""
    source_type: str = ""
    library_name: str = ""
    documentation: str = ""
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
    source_type: str = ""
    source_path: str = ""
    builtin: bool = False
    keyword_count: int = 0
    last_updated: str | None = None


class LibraryListResponse(BaseModel):
    libraries: list[LibrarySummaryResponse] = Field(default_factory=list)


class LibraryDetailResponse(LibrarySummaryResponse):
    keywords: list[LibraryKeywordResponse] = Field(default_factory=list)
