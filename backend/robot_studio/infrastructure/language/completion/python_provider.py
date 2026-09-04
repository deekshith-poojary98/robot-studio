"""Python completion providers (buffer AST + project index + Jedi)."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path

from robot_studio.domain.interfaces.completion import (
    CompletionCandidate,
    CompletionProvider,
    CompletionRequestContext,
    match_score,
)
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.infrastructure.language.python_jedi import (
    jedi_available,
    jedi_completions,
)
from robot_studio.infrastructure.language.python_language import (
    is_python_path,
    python_buffer_completions,
)
from robot_studio.infrastructure.process_utils import run_blocking

SearchSymbols = Callable[..., Awaitable[list[dict]]]
ResolvePython = Callable[[], Path]
ResolveProjectRoot = Callable[[], Path | None]


@dataclass
class PythonBufferCompletionProvider(CompletionProvider):
    """Tier 1 — symbols and keywords from the open ``.py`` buffer."""

    @property
    def provider_id(self) -> str:
        return "python_buffer"

    @property
    def label(self) -> str:
        return "Python buffer"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"python", "python_attr"})

    @property
    def base_priority(self) -> int:
        return 85

    def accepts(self, ctx: CompletionRequestContext) -> bool:
        if not is_python_path(ctx.file_path):
            return False
        return super().accepts(ctx)

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        raw = python_buffer_completions(
            ctx.content,
            line=ctx.line,
            column=ctx.column,
            prefix=ctx.prefix,
            context=ctx.context,
            attribute_base=ctx.attribute_base,
        )
        return [
            CompletionCandidate(
                label=str(item["label"]),
                kind=str(item.get("kind") or "keyword"),
                detail=str(item.get("detail") or ""),
                documentation=str(item.get("documentation") or ""),
                insert_text=str(item.get("insert_text") or item["label"]),
                provider_id=self.provider_id,
                match_score=match_score(str(item["label"]), ctx.prefix),
                base_priority=self.base_priority,
            )
            for item in raw
        ]


@dataclass
class PythonIndexCompletionProvider(CompletionProvider):
    """Tier 2 — project ``.py`` symbols from the workspace index."""

    search_symbols: SearchSymbols

    @property
    def provider_id(self) -> str:
        return "python_index"

    @property
    def label(self) -> str:
        return "Python project"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"python", "python_attr"})

    @property
    def base_priority(self) -> int:
        return 75

    def accepts(self, ctx: CompletionRequestContext) -> bool:
        if not is_python_path(ctx.file_path):
            return False
        if ctx.context == "python_attr":
            # Attribute completions are buffer-local (self. / Class.).
            return False
        return super().accepts(ctx)

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        prefix = ctx.prefix
        if len(prefix) < 1:
            return []
        out: list[CompletionCandidate] = []
        seen: set[str] = set()

        for kind in (SymbolKind.KEYWORD, SymbolKind.LIBRARY, SymbolKind.VARIABLE, SymbolKind.FILE):
            try:
                results = await self.search_symbols(prefix, kind=kind, limit=60)
            except Exception:  # noqa: BLE001, S112
                continue
            for item in results:
                path = str(item.get("file_path") or "")
                if not is_python_path(path):
                    continue
                # Skip the file currently being edited — buffer provider owns it.
                try:
                    if Path(path).resolve() == Path(ctx.file_path).expanduser().resolve():
                        continue
                except OSError:
                    if path == ctx.file_path:
                        continue
                raw_name = str(item.get("name") or "")
                if not raw_name:
                    continue
                label = _python_ident(raw_name, kind=str(item.get("kind") or ""))
                if not label or label in seen:
                    continue
                if prefix and not label.casefold().startswith(prefix.casefold()):
                    # Spaced RF keyword form may not match snake_case prefix.
                    snake = raw_name.replace(" ", "_")
                    if snake.casefold().startswith(prefix.casefold()):
                        label = snake
                    else:
                        continue
                seen.add(label)
                kind_label = _kind_label(str(item.get("kind") or ""), path)
                out.append(
                    CompletionCandidate(
                        label=label,
                        kind=kind_label,
                        detail=str(item.get("detail") or Path(path).name),
                        documentation=str(item.get("documentation") or ""),
                        insert_text=label,
                        provider_id=self.provider_id,
                        match_score=match_score(label, prefix),
                        base_priority=self.base_priority,
                    ),
                )
        return out


@dataclass
class PythonJediCompletionProvider(CompletionProvider):
    """Tier 3 — stdlib + venv packages via Jedi (active environment interpreter)."""

    resolve_python: ResolvePython
    resolve_project_root: ResolveProjectRoot

    @property
    def provider_id(self) -> str:
        return "python_jedi"

    @property
    def label(self) -> str:
        return "Python (Jedi)"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"python", "python_attr"})

    @property
    def base_priority(self) -> int:
        return 92

    def accepts(self, ctx: CompletionRequestContext) -> bool:
        if not jedi_available():
            return False
        if not is_python_path(ctx.file_path):
            return False
        return super().accepts(ctx)

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        try:
            python_executable = self.resolve_python()
        except Exception:  # noqa: BLE001 — no active environment
            return []

        raw = await run_blocking(
            jedi_completions,
            ctx.content,
            ctx.file_path,
            ctx.line,
            ctx.column,
            python_executable,
            self.resolve_project_root(),
            prefix=ctx.prefix,
        )
        return [
            CompletionCandidate(
                label=str(item["label"]),
                kind=str(item.get("kind") or "variable"),
                detail=str(item.get("detail") or ""),
                documentation=str(item.get("documentation") or ""),
                insert_text=str(item.get("insert_text") or item["label"]),
                provider_id=self.provider_id,
                match_score=match_score(str(item["label"]), ctx.prefix),
                base_priority=self.base_priority,
            )
            for item in raw
        ]


def _python_ident(name: str, *, kind: str) -> str:
    """Prefer snake_case for Python editing; keep class / module names."""
    if kind == SymbolKind.FILE.value:
        return Path(name).stem if "/" in name or name.endswith(".py") else name
    if " " in name:
        return name.replace(" ", "_")
    return name


def _kind_label(kind: str, path: str) -> str:
    if kind == SymbolKind.LIBRARY.value:
        return "class" if Path(path).suffix.lower() == ".py" else "library"
    if kind == SymbolKind.KEYWORD.value:
        return "function"
    if kind == SymbolKind.VARIABLE.value:
        return "variable"
    if kind == SymbolKind.FILE.value:
        return "module"
    return kind
