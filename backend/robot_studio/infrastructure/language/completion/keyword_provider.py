"""Keyword / variable / index symbol completion providers."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any

from robot_studio.domain.interfaces.completion import (
    CompletionCandidate,
    CompletionProvider,
    CompletionRequestContext,
    match_score,
    matches_prefix,
)
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.infrastructure.language.builtin_keywords import BUILTIN_KEYWORDS

_POPULAR_BUILTIN = [
    "Log",
    "Log To Console",
    "Should Be Equal",
    "Should Be True",
    "Set Variable",
    "Create List",
    "Create Dictionary",
    "Fail",
    "Sleep",
    "No Operation",
    "Run Keyword",
    "Evaluate",
    "Get Length",
    "Get Variable Value",
    "Wait Until Keyword Succeeds",
]


ResolveLibrary = Callable[[str], Awaitable[dict[str, Any]]]
ImportedLibraries = Callable[[str], list[tuple[str, str | None]]]
SearchSymbols = Callable[..., Awaitable[list[dict]]]


@dataclass
class KeywordCompletionProvider(CompletionProvider):
    """BuiltIn + imported library keywords (libdoc) + indexed keywords."""

    resolve_library: ResolveLibrary
    imported_library_entries: ImportedLibraries
    search_symbols: SearchSymbols

    @property
    def provider_id(self) -> str:
        return "keywords"

    @property
    def label(self) -> str:
        return "Keywords"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"library", "keyword_call", "keyword", "control"})

    @property
    def base_priority(self) -> int:
        return 60

    def accepts(self, ctx: CompletionRequestContext) -> bool:
        # Argument sites are owned by NamedArgumentCompletionProvider.
        if ctx.context == "argument":
            return False
        return super().accepts(ctx)

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        prefix = ctx.prefix
        out: list[CompletionCandidate] = []

        builtin_source = BUILTIN_KEYWORDS
        if len(prefix) < 1:
            builtin_source = _POPULAR_BUILTIN
        for name in builtin_source:
            if matches_prefix(name, prefix):
                out.append(
                    CompletionCandidate(
                        label=name,
                        kind="keyword",
                        detail="BuiltIn library",
                        documentation="BuiltIn library keyword (not RF DSL).",
                        insert_text=name,
                        provider_id=self.provider_id,
                        match_score=match_score(name, prefix),
                        base_priority=self.base_priority,
                    ),
                )

        if len(prefix) >= 1:
            try:
                resolved = await self.resolve_library("BuiltIn")
                if resolved.get("available"):
                    for name in resolved.get("keywords") or []:
                        label = str(name)
                        if matches_prefix(label, prefix):
                            out.append(
                                CompletionCandidate(
                                    label=label,
                                    kind="keyword",
                                    detail="BuiltIn library",
                                    documentation="BuiltIn library keyword (not RF DSL).",
                                    insert_text=label,
                                    provider_id=self.provider_id,
                                    match_score=match_score(label, prefix),
                                    base_priority=self.base_priority + 2,
                                ),
                            )
            except Exception:  # noqa: BLE001
                pass

            if ctx.content:
                try:
                    for lib_name, alias in self.imported_library_entries(ctx.content):
                        if lib_name.casefold() == "builtin":
                            continue
                        resolved = await self.resolve_library(lib_name)
                        if not resolved.get("available"):
                            continue
                        display = str(resolved.get("name") or lib_name)
                        info = resolved.get("keyword_info") or {}
                        for kw in resolved.get("keywords") or []:
                            kw_name = str(kw)
                            docs = str(
                                (info.get(kw_name.casefold()) or {}).get("documentation")
                                or "",
                            )
                            if alias:
                                qualified = f"{alias}.{kw_name}"
                                if matches_prefix(qualified, prefix) or matches_prefix(
                                    kw_name,
                                    prefix,
                                ):
                                    out.append(
                                        CompletionCandidate(
                                            label=qualified,
                                            kind="keyword",
                                            detail=f"{display} (as {alias})",
                                            documentation=docs,
                                            insert_text=qualified,
                                            provider_id=self.provider_id,
                                            match_score=match_score(qualified, prefix),
                                            base_priority=self.base_priority + 5,
                                        ),
                                    )
                            elif matches_prefix(kw_name, prefix):
                                out.append(
                                    CompletionCandidate(
                                        label=kw_name,
                                        kind="keyword",
                                        detail=f"{display} library",
                                        documentation=docs,
                                        insert_text=kw_name,
                                        provider_id=self.provider_id,
                                        match_score=match_score(kw_name, prefix),
                                        base_priority=self.base_priority + 5,
                                    ),
                                )
                except Exception:  # noqa: BLE001
                    pass

        # Indexed user keywords / suites
        try:
            results = await self.search_symbols(
                prefix,
                kind=SymbolKind.KEYWORD,
                limit=80,
            )
            for item in results:
                name = str(item.get("name") or "")
                if not name:
                    continue
                out.append(
                    CompletionCandidate(
                        label=name,
                        kind=str(item.get("kind") or "keyword"),
                        detail=str(item.get("detail") or "Indexed"),
                        documentation=str(item.get("documentation") or ""),
                        insert_text=name,
                        provider_id=self.provider_id,
                        match_score=match_score(name, prefix),
                        base_priority=self.base_priority + 8,
                    ),
                )
        except Exception:  # noqa: BLE001
            pass

        return out


@dataclass
class VariableCompletionProvider(CompletionProvider):
    """Indexed variables (+ automatic Robot vars via kind filter)."""

    search_symbols: SearchSymbols

    @property
    def provider_id(self) -> str:
        return "variables"

    @property
    def label(self) -> str:
        return "Variables"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"variable", "keyword_call", "keyword", "control"})

    @property
    def base_priority(self) -> int:
        return 65

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        # Only flood variables when typing a var prefix or in Variables section.
        if ctx.context != "variable" and not ctx.prefix.startswith(("${", "@{", "&{", "%{")):
            if len(ctx.prefix) < 2:
                return []
        out: list[CompletionCandidate] = []
        try:
            results = await self.search_symbols(
                ctx.prefix.lstrip("${}@&%"),
                kind=SymbolKind.VARIABLE,
                limit=60,
            )
            for item in results:
                name = str(item.get("name") or "")
                if not name:
                    continue
                # Ensure RF variable braces when completing bare names
                insert = name
                if not name.startswith(("${", "@{", "&{", "%{")):
                    insert = f"${{{name}}}"
                if not matches_prefix(insert, ctx.prefix) and not matches_prefix(
                    name,
                    ctx.prefix,
                ):
                    continue
                label = insert if ctx.prefix.startswith(("${", "@{", "&{", "%{")) else name
                out.append(
                    CompletionCandidate(
                        label=label if label.startswith("$") else insert,
                        kind="variable",
                        detail=str(item.get("detail") or "Indexed variable"),
                        insert_text=insert,
                        provider_id=self.provider_id,
                        match_score=match_score(insert, ctx.prefix),
                        base_priority=self.base_priority,
                    ),
                )
        except Exception:  # noqa: BLE001
            pass
        return out


@dataclass
class IndexSymbolCompletionProvider(CompletionProvider):
    """Libraries / resources / settings from the symbol index (context-filtered)."""

    search_symbols: SearchSymbols

    @property
    def provider_id(self) -> str:
        return "index"

    @property
    def label(self) -> str:
        return "Index"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset(
            {
                "library",
                "resource",
                "setting",
                "keyword",
                "keyword_call",
                "section",
            },
        )

    @property
    def base_priority(self) -> int:
        return 55

    def _kind(self, ctx: CompletionRequestContext) -> SymbolKind | None:
        return {
            "library": SymbolKind.LIBRARY,
            "resource": SymbolKind.RESOURCE,
            "setting": SymbolKind.SETTING,
            "local_setting": SymbolKind.SETTING,
            "section": SymbolKind.SETTING,
            "keyword": SymbolKind.KEYWORD,
            "keyword_call": SymbolKind.KEYWORD,
        }.get(ctx.context)

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        kind = self._kind(ctx)
        if kind in {SymbolKind.KEYWORD, SymbolKind.VARIABLE}:
            # Handled by dedicated providers to avoid duplicate floods.
            return []
        out: list[CompletionCandidate] = []
        try:
            results = await self.search_symbols(ctx.prefix, kind=kind, limit=40)
            for item in results:
                name = str(item.get("name") or "")
                if not name or not matches_prefix(name, ctx.prefix):
                    continue
                out.append(
                    CompletionCandidate(
                        label=name,
                        kind=str(item.get("kind") or "symbol"),
                        detail=str(item.get("detail") or "Indexed"),
                        insert_text=name,
                        provider_id=self.provider_id,
                        match_score=match_score(name, ctx.prefix),
                        base_priority=self.base_priority,
                    ),
                )
        except Exception:  # noqa: BLE001
            pass
        return out
