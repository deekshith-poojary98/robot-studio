"""Application facade for language features over IndexStore."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.domain.interfaces.language import LanguageService


class LanguageValidationError(Exception):
    """Raised when a language request cannot be satisfied."""


@dataclass
class LanguageFacade:
    context: WorkspaceContext
    language: LanguageService

    def _require_workspace(self) -> None:
        if self.context.workspace is None:
            raise LanguageValidationError("Open a workspace before using language features")

    async def definition(
        self,
        *,
        name: str | None = None,
        symbol_id: str | None = None,
        kind: str | None = None,
        file_path: str | None = None,
        line: int | None = None,
        column: int | None = None,
        content: str | None = None,
    ) -> dict | None:
        self._require_workspace()
        if not name and not symbol_id and not (content and file_path and line):
            raise LanguageValidationError("Provide name, symbol_id, or cursor context")
        return await self.language.definition(
            {
                "name": name,
                "symbol_id": symbol_id,
                "kind": kind,
                "file_path": file_path,
                "line": line,
                "column": column,
                "content": content,
            },
        )

    async def references(
        self,
        *,
        name: str | None = None,
        symbol_id: str | None = None,
        kind: str | None = None,
        file_path: str | None = None,
        line: int | None = None,
        column: int | None = None,
        content: str | None = None,
    ) -> list[dict]:
        self._require_workspace()
        if not name and not symbol_id and not (content and file_path and line):
            raise LanguageValidationError("Provide name, symbol_id, or cursor context")
        return await self.language.references(
            {
                "name": name,
                "symbol_id": symbol_id,
                "kind": kind,
                "file_path": file_path,
                "line": line,
                "column": column,
                "content": content,
            },
        )

    async def hover(
        self,
        *,
        name: str | None = None,
        symbol_id: str | None = None,
        kind: str | None = None,
        file_path: str | None = None,
        line: int | None = None,
        column: int | None = None,
        content: str | None = None,
    ) -> dict | None:
        self._require_workspace()
        if not name and not symbol_id and not (content and file_path and line):
            raise LanguageValidationError("Provide name, symbol_id, or cursor context")
        return await self.language.hover(
            {
                "name": name,
                "symbol_id": symbol_id,
                "kind": kind,
                "file_path": file_path,
                "line": line,
                "column": column,
                "content": content,
            },
        )

    async def completion(
        self,
        *,
        file_path: str,
        line: int,
        column: int,
        content: str,
        query: str = "",
    ) -> list[dict]:
        self._require_workspace()
        if not file_path:
            raise LanguageValidationError("Provide file path")
        return await self.language.completion(
            {
                "file_path": file_path,
                "line": line,
                "column": column,
                "content": content,
                "query": query,
            },
        )

    async def record_completion_usage(
        self,
        *,
        label: str,
        kind: str = "",
    ) -> None:
        self._require_workspace()
        if not label.strip():
            raise LanguageValidationError("Provide a completion label")
        record = getattr(self.language, "record_completion_usage", None)
        if record is None:
            return
        await record(label=label, kind=kind)

    async def diagnostics(self, *, file_path: str, content: str) -> list[dict]:
        self._require_workspace()
        if not file_path:
            raise LanguageValidationError("Provide file path")
        return await self.language.diagnostics(
            {"file_path": file_path, "content": content},
        )

    async def format_document(
        self,
        *,
        file_path: str,
        content: str,
        start_line: int | None = None,
        end_line: int | None = None,
    ) -> str:
        self._require_workspace()
        if not file_path:
            raise LanguageValidationError("Provide file path")
        return await self.language.format_document(
            {
                "file_path": file_path,
                "content": content,
                "start_line": start_line,
                "end_line": end_line,
            },
        )

    async def signature_help(
        self,
        *,
        file_path: str,
        line: int,
        column: int,
        content: str,
    ) -> dict | None:
        self._require_workspace()
        if not file_path:
            raise LanguageValidationError("Provide file path")
        return await self.language.signature_help(
            {
                "file_path": file_path,
                "line": line,
                "column": column,
                "content": content,
            },
        )

    async def document_symbols(self, file_path: str) -> list[dict]:
        self._require_workspace()
        if not file_path:
            raise LanguageValidationError("Provide file path")
        store = getattr(self.language, "store", None)
        if store is None:
            raise LanguageValidationError("Language service does not expose IndexStore")
        return await store.symbols_for_file(Path(file_path))

    async def workspace_symbols(self, query: str = "", *, limit: int = 200) -> list[dict]:
        self._require_workspace()
        store = getattr(self.language, "store", None)
        if store is None:
            raise LanguageValidationError("Language service does not expose IndexStore")
        return await store.search_symbols(query, limit=limit)
