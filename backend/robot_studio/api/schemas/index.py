from datetime import datetime

from pydantic import BaseModel, Field

from robot_studio.domain.models import IndexStatus


class IndexStatusResponse(BaseModel):
    state: str
    files_indexed: int = 0
    keywords_indexed: int = 0
    libraries_indexed: int = 0
    variables_indexed: int = 0
    symbols_indexed: int = 0
    last_indexed_at: datetime | None = None
    message: str = ""
    errors: list[str] = Field(default_factory=list)


class SymbolResponse(BaseModel):
    id: str
    name: str
    kind: str
    file_path: str
    line: int = 1
    project_id: str | None = None
    workspace_id: str | None = None
    documentation: str = ""
    detail: str = ""
    last_modified: float | None = None
    definitions: list["SymbolResponse"] | None = None


class SearchResponse(BaseModel):
    results: list[SymbolResponse] = Field(default_factory=list)


class ReferenceResponse(BaseModel):
    symbol_id: str = ""
    name: str
    file_path: str
    line: int = 1
    project_id: str | None = None
    context: str = ""


class ReferenceListResponse(BaseModel):
    references: list[ReferenceResponse] = Field(default_factory=list)


class HoverResponse(BaseModel):
    name: str
    kind: str
    file_path: str
    line: int = 1
    documentation: str = ""
    detail: str = ""
    id: str = ""


def to_index_status(status: IndexStatus) -> IndexStatusResponse:
    return IndexStatusResponse(
        state=status.state,
        files_indexed=status.files_indexed,
        keywords_indexed=status.keywords_indexed,
        libraries_indexed=status.libraries_indexed,
        variables_indexed=status.variables_indexed,
        symbols_indexed=status.symbols_indexed,
        last_indexed_at=status.last_indexed_at,
        message=status.message,
        errors=status.errors,
    )


def to_symbol_response(item: dict) -> SymbolResponse:
    nested = item.get("definitions")
    definitions = None
    if isinstance(nested, list) and nested:
        definitions = [
            SymbolResponse(
                id=str(d["id"]),
                name=str(d["name"]),
                kind=str(d["kind"]),
                file_path=str(d["file_path"]),
                line=int(d.get("line") or 1),
                project_id=d.get("project_id"),
                workspace_id=d.get("workspace_id"),
                documentation=d.get("documentation") or "",
                detail=d.get("detail") or "",
                last_modified=d.get("last_modified"),
            )
            for d in nested
            if isinstance(d, dict) and d.get("id") and d.get("name") and d.get("file_path")
        ]
    return SymbolResponse(
        id=item["id"],
        name=item["name"],
        kind=item["kind"],
        file_path=item["file_path"],
        line=int(item.get("line") or 1),
        project_id=item.get("project_id"),
        workspace_id=item.get("workspace_id"),
        documentation=item.get("documentation") or "",
        detail=item.get("detail") or "",
        last_modified=item.get("last_modified"),
        definitions=definitions,
    )
