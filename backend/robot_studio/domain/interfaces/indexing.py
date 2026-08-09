from abc import ABC, abstractmethod
from enum import Enum
from pathlib import Path
from uuid import UUID


class SymbolKind(str, Enum):
    KEYWORD = "keyword"
    VARIABLE = "variable"
    LIBRARY = "library"
    RESOURCE = "resource"
    TEST_SUITE = "test_suite"
    TEST_CASE = "test_case"
    SETTING = "setting"
    TAG = "tag"
    DOCUMENTATION = "documentation"
    FILE = "file"


class IndexScope(str, Enum):
    WORKSPACE = "workspace"
    PROJECT = "project"
    FILE = "file"
    ENVIRONMENT = "environment"


class IndexStore(ABC):
    @abstractmethod
    async def initialize(self) -> None: ...

    @abstractmethod
    async def invalidate(self, scope: IndexScope, scope_id: str | None = None) -> None: ...

    @abstractmethod
    async def upsert_symbols(self, symbols: list) -> None: ...

    @abstractmethod
    async def remove_file(self, file_path: Path) -> int: ...

    @abstractmethod
    async def get_file_mtime(self, file_path: Path) -> float | None: ...

    @abstractmethod
    async def search_symbols(
        self,
        query: str,
        *,
        project_id: UUID | None = None,
        workspace_id: UUID | None = None,
        kind: SymbolKind | None = None,
        limit: int = 100,
    ) -> list[dict]: ...

    @abstractmethod
    async def find_references(self, symbol_id: str) -> list[dict]: ...

    @abstractmethod
    async def get_symbol(self, symbol_id: str) -> dict | None: ...

    @abstractmethod
    async def find_definition(self, name: str, *, kind: SymbolKind | None = None) -> dict | None: ...

    @abstractmethod
    async def symbols_for_file(self, file_path: Path) -> list[dict]: ...

    @abstractmethod
    async def status(self, workspace_id: UUID | None = None) -> dict: ...

    @abstractmethod
    async def composition_by_kind(self, workspace_id: UUID | None = None) -> dict[str, int]:
        """Return {kind: count} for indexed symbols."""

    @abstractmethod
    async def composition_by_file(
        self, workspace_id: UUID | None = None
    ) -> list[dict]:
        """Return [{file_path, counts: {kind: count}}] for indexed symbols."""


class FileWatcher(ABC):
    @abstractmethod
    async def start(self) -> None: ...

    @abstractmethod
    async def stop(self) -> None: ...

    @abstractmethod
    def watch_path(self, path: Path) -> None: ...

    @abstractmethod
    def unwatch_path(self, path: Path) -> None: ...
