"""Search provider ports — content and symbol search share one composition surface."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID


@dataclass(frozen=True)
class SearchMatchEnclosing:
    """Optional semantic decoration from the index (not used for matching)."""

    kind: str
    name: str
    line: int


@dataclass(frozen=True)
class ContentMatch:
    line: int
    column: int
    text: str
    before: list[str] = field(default_factory=list)
    after: list[str] = field(default_factory=list)
    enclosing: SearchMatchEnclosing | None = None


@dataclass(frozen=True)
class ContentFileHits:
    path: str
    match_count: int
    matches: list[ContentMatch]


@dataclass(frozen=True)
class ContentSearchResult:
    query: str
    truncated: bool
    files_scanned: int
    files: list[ContentFileHits]


@dataclass(frozen=True)
class SymbolSearchHit:
    raw: dict


@dataclass(frozen=True)
class SymbolSearchResult:
    query: str
    results: list[SymbolSearchHit]


class SearchProvider(ABC):
    """Pluggable search backend for Unified Search composition later."""

    @property
    @abstractmethod
    def provider_id(self) -> str:
        """Stable id, e.g. ``content`` or ``symbols``."""

    @property
    @abstractmethod
    def label(self) -> str:
        """Human label for UI grouping."""

    @abstractmethod
    async def is_available(self) -> bool:
        ...


class ContentSearchProvider(SearchProvider):
    @property
    def provider_id(self) -> str:
        return "content"

    @property
    def label(self) -> str:
        return "Files"

    @abstractmethod
    async def search_content(
        self,
        query: str,
        *,
        root: Path | None = None,
        project_id: UUID | None = None,
        workspace_id: UUID | None = None,
        limit: int = 500,
        context_lines: int = 1,
        extensions: frozenset[str] | None = None,
        cancel_check: Callable[[], bool] | None = None,
    ) -> ContentSearchResult:
        ...


class SymbolSearchProvider(SearchProvider):
    @property
    def provider_id(self) -> str:
        return "symbols"

    @property
    def label(self) -> str:
        return "Symbols"

    @abstractmethod
    async def search_symbols(
        self,
        query: str,
        *,
        kind: str | None = None,
        limit: int = 100,
    ) -> SymbolSearchResult:
        ...
