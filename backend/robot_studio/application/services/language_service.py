"""Application facade for language features over IndexStore."""

from __future__ import annotations

from dataclasses import dataclass

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

    async def definition(self, *, name: str | None = None, symbol_id: str | None = None, kind: str | None = None) -> dict | None:
        self._require_workspace()
        if not name and not symbol_id:
            raise LanguageValidationError("Provide name or symbol_id")
        return await self.language.definition(
            {"name": name, "symbol_id": symbol_id, "kind": kind},
        )

    async def references(self, *, name: str | None = None, symbol_id: str | None = None, kind: str | None = None) -> list[dict]:
        self._require_workspace()
        if not name and not symbol_id:
            raise LanguageValidationError("Provide name or symbol_id")
        return await self.language.references(
            {"name": name, "symbol_id": symbol_id, "kind": kind},
        )

    async def hover(self, *, name: str | None = None, symbol_id: str | None = None, kind: str | None = None) -> dict | None:
        self._require_workspace()
        if not name and not symbol_id:
            raise LanguageValidationError("Provide name or symbol_id")
        return await self.language.hover(
            {"name": name, "symbol_id": symbol_id, "kind": kind},
        )
