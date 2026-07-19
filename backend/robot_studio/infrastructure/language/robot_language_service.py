"""Index-backed Language Service implementation."""

from __future__ import annotations

from dataclasses import dataclass, field

from robot_studio.core.events import EventBus, IndexUpdated
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.interfaces.language import LanguageService
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore


@dataclass
class RobotLanguageService(LanguageService):
    store: SqliteIndexStore
    event_bus: EventBus | None = None
    _cache_generation: int = field(default=0, init=False)
    _subscribed: bool = field(default=False, init=False)

    def start(self) -> None:
        if self._subscribed or self.event_bus is None:
            return
        self.event_bus.subscribe(IndexUpdated, self._on_index_updated)
        self._subscribed = True

    async def _on_index_updated(self, event: IndexUpdated) -> None:
        _ = event
        self._cache_generation += 1

    async def completion(self, request: dict) -> list[dict]:
        # Autocomplete UI is out of scope for this milestone.
        query = str(request.get("query") or request.get("prefix") or "")
        kind_raw = request.get("kind")
        kind = SymbolKind(kind_raw) if kind_raw else None
        results = await self.store.search_symbols(query, kind=kind, limit=50)
        return [
            {
                "label": item["name"],
                "kind": item["kind"],
                "detail": item.get("detail") or "",
                "documentation": item.get("documentation") or "",
                "insert_text": item["name"],
            }
            for item in results
        ]

    async def hover(self, request: dict) -> dict | None:
        symbol = await self._resolve(request)
        if symbol is None:
            return None
        return {
            "name": symbol["name"],
            "kind": symbol["kind"],
            "file_path": symbol["file_path"],
            "line": symbol["line"],
            "documentation": symbol.get("documentation") or "",
            "detail": symbol.get("detail") or "",
            "id": symbol["id"],
        }

    async def diagnostics(self, request: dict) -> list[dict]:
        # Basic indexing errors only — no semantic diagnostics yet.
        _ = request
        return []

    async def definition(self, request: dict) -> dict | None:
        symbol = await self._resolve(request)
        if symbol is None:
            return None
        return {
            "id": symbol["id"],
            "name": symbol["name"],
            "kind": symbol["kind"],
            "file_path": symbol["file_path"],
            "line": symbol["line"],
            "documentation": symbol.get("documentation") or "",
            "detail": symbol.get("detail") or "",
        }

    async def references(self, request: dict) -> list[dict]:
        symbol = await self._resolve(request)
        if symbol is None:
            return []
        refs = await self.store.find_references(symbol["id"])
        if not refs:
            # Fallback: search symbol name usages indexed as references.
            refs = await self.store.find_references(symbol["name"])
        return refs

    async def format_document(self, request: dict) -> str:
        content = str(request.get("content") or "")
        return content

    async def _resolve(self, request: dict) -> dict | None:
        symbol_id = request.get("symbol_id")
        if symbol_id:
            return await self.store.get_symbol(str(symbol_id))
        name = request.get("name") or request.get("symbol") or request.get("query")
        if not name:
            return None
        kind_raw = request.get("kind")
        kind = None
        if kind_raw:
            try:
                kind = SymbolKind(str(kind_raw))
            except ValueError:
                kind = None
        return await self.store.find_definition(str(name), kind=kind)
