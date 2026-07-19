from abc import ABC, abstractmethod
from enum import Enum
from uuid import UUID


class SymbolKind(str, Enum):
    KEYWORD = "keyword"
    VARIABLE = "variable"
    LIBRARY = "library"
    RESOURCE = "resource"


class IndexScope(str, Enum):
    WORKSPACE = "workspace"
    PROJECT = "project"
    FILE = "file"
    ENVIRONMENT = "environment"


class IndexStore(ABC):
    @abstractmethod
    async def invalidate(self, scope: IndexScope, scope_id: str | None = None) -> None: ...

    @abstractmethod
    async def search_symbols(
        self,
        query: str,
        *,
        project_id: UUID | None = None,
        kind: SymbolKind | None = None,
    ) -> list[dict]: ...

    @abstractmethod
    async def find_references(self, symbol_id: str) -> list[dict]: ...
