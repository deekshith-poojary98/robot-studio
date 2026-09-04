"""File / resource path completions (Library Explorer Phase 3 will expand this)."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from robot_studio.domain.interfaces.completion import (
    CompletionCandidate,
    CompletionProvider,
    CompletionRequestContext,
    match_score,
    matches_prefix,
)
from robot_studio.domain.interfaces.indexing import SymbolKind

SearchSymbols = Callable[..., Awaitable[list[dict]]]


@dataclass
class FilesCompletionProvider(CompletionProvider):
    """Suggest Resource / Variables file paths from the symbol index."""

    search_symbols: SearchSymbols

    @property
    def provider_id(self) -> str:
        return "files"

    @property
    def label(self) -> str:
        return "Files"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"resource", "library", "setting"})

    @property
    def base_priority(self) -> int:
        return 58

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        if ctx.context not in {"resource", "library"} and ctx.section != "settings":
            return []
        if len(ctx.prefix) < 1:
            return []
        kind = (
            SymbolKind.LIBRARY
            if ctx.context == "library"
            else SymbolKind.RESOURCE
        )
        out: list[CompletionCandidate] = []
        try:
            results = await self.search_symbols(ctx.prefix, kind=kind, limit=40)
            for item in results:
                name = str(item.get("name") or "")
                path = str(item.get("file_path") or item.get("detail") or "")
                label = name or path
                if not label or not matches_prefix(label, ctx.prefix):
                    continue
                out.append(
                    CompletionCandidate(
                        label=label,
                        kind=str(item.get("kind") or kind.value),
                        detail=path or "Workspace file",
                        insert_text=label,
                        provider_id=self.provider_id,
                        match_score=match_score(label, ctx.prefix),
                        base_priority=self.base_priority,
                    ),
                )
        except Exception:  # noqa: BLE001, S110
            pass
        return out
