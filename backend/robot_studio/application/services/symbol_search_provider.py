"""Symbol search provider — thin adapter over IndexService."""

from __future__ import annotations

from robot_studio.application.services.index_service import IndexService
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.interfaces.search import (
    SymbolSearchHit,
    SymbolSearchProvider,
    SymbolSearchResult,
)


class IndexSymbolSearchProvider(SymbolSearchProvider):
    def __init__(self, index_service: IndexService) -> None:
        self._index = index_service

    async def is_available(self) -> bool:
        try:
            self._index._require_workspace()  # noqa: SLF001
            return True
        except Exception:  # noqa: BLE001
            return False

    async def search_symbols(
        self,
        query: str,
        *,
        kind: str | None = None,
        limit: int = 100,
    ) -> SymbolSearchResult:
        symbol_kind = SymbolKind(kind) if kind else None
        raw = await self._index.search(query, kind=symbol_kind, limit=limit)
        return SymbolSearchResult(
            query=query,
            results=[SymbolSearchHit(raw=item) for item in raw],
        )
