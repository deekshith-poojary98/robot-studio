"""Content search API schemas."""

from __future__ import annotations

from robot_studio.domain.interfaces.search import ContentSearchResult
from pydantic import BaseModel, Field


class EnclosingSymbolResponse(BaseModel):
    kind: str
    name: str
    line: int


class ContentMatchResponse(BaseModel):
    line: int
    column: int
    text: str
    before: list[str] = Field(default_factory=list)
    after: list[str] = Field(default_factory=list)
    enclosing: EnclosingSymbolResponse | None = None


class ContentFileHitsResponse(BaseModel):
    path: str
    match_count: int
    matches: list[ContentMatchResponse]


class ContentSearchResponse(BaseModel):
    query: str
    truncated: bool
    files_scanned: int
    files: list[ContentFileHitsResponse]


def to_content_search(result: ContentSearchResult) -> ContentSearchResponse:
    files = []
    for file_hits in result.files:
        matches = []
        for match in file_hits.matches:
            enclosing = None
            if match.enclosing is not None:
                enclosing = EnclosingSymbolResponse(
                    kind=match.enclosing.kind,
                    name=match.enclosing.name,
                    line=match.enclosing.line,
                )
            matches.append(
                ContentMatchResponse(
                    line=match.line,
                    column=match.column,
                    text=match.text,
                    before=list(match.before),
                    after=list(match.after),
                    enclosing=enclosing,
                ),
            )
        files.append(
            ContentFileHitsResponse(
                path=file_hits.path,
                match_count=file_hits.match_count,
                matches=matches,
            ),
        )
    return ContentSearchResponse(
        query=result.query,
        truncated=result.truncated,
        files_scanned=result.files_scanned,
        files=files,
    )
