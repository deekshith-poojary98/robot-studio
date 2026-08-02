from pydantic import BaseModel, Field


class CompletionItemResponse(BaseModel):
    label: str
    kind: str
    detail: str = ""
    documentation: str = ""
    insert_text: str = ""


class CompletionListResponse(BaseModel):
    items: list[CompletionItemResponse] = Field(default_factory=list)


class CompletionRequest(BaseModel):
    file_path: str
    line: int = 1
    column: int = 1
    content: str = ""
    query: str = ""


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
    documentation: str = ""


class SignatureHelpResponse(BaseModel):
    keyword: str
    documentation: str = ""
    detail: str = ""
    active_parameter: int = 0
    parameters: list[SignatureParameterResponse] = Field(default_factory=list)


class SignatureHelpRequest(BaseModel):
    file_path: str
    line: int = 1
    column: int = 1
    content: str = ""
