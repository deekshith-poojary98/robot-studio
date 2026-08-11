"""Completion provider ports — buffer, keywords, libraries, files share one pipeline."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class CompletionRequestContext:
    """Cursor + buffer context for all providers."""

    file_path: str
    content: str
    line: int
    column: int
    prefix: str
    context: str
    section: str = ""
    project_id: str | None = None
    keyword: str = ""
    arguments: tuple[str, ...] = ()
    active_parameter: int = 0
    current_argument: str = ""


@dataclass
class CompletionCandidate:
    """Single ranked completion item from one provider."""

    label: str
    kind: str
    detail: str = ""
    documentation: str = ""
    insert_text: str = ""
    provider_id: str = ""
    # Ranking signals (filled by providers / pipeline)
    match_score: float = 0.0
    usage_count: int = 0
    buffer_frequency: int = 0
    base_priority: int = 0

    def to_api(self) -> dict[str, Any]:
        return {
            "label": self.label,
            "kind": self.kind,
            "detail": self.detail,
            "documentation": self.documentation,
            "insert_text": self.insert_text or self.label,
            "provider": self.provider_id,
        }


class CompletionProvider(ABC):
    """Pluggable completion source for the ranking pipeline."""

    @property
    @abstractmethod
    def provider_id(self) -> str:
        """Stable id, e.g. ``buffer`` or ``keywords``."""

    @property
    @abstractmethod
    def label(self) -> str:
        """Human label for UI grouping / Library Explorer later."""

    @property
    @abstractmethod
    def supported_contexts(self) -> frozenset[str]:
        """Contexts this provider may contribute to (empty = all)."""

    @property
    def base_priority(self) -> int:
        """Higher = preferred when scores tie (0–100)."""
        return 50

    def accepts(self, ctx: CompletionRequestContext) -> bool:
        if not self.supported_contexts:
            return True
        return ctx.context in self.supported_contexts

    @abstractmethod
    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        ...


def matches_prefix(label: str, prefix: str) -> bool:
    """Prefix / word-start match — not substring (``a`` must not hit ``RANGE``)."""
    if not prefix:
        return True
    needle = prefix.casefold()
    hay = label.casefold()
    if hay.startswith(needle):
        return True
    import re

    return any(
        part.startswith(needle)
        for part in re.split(r"[\s.]+", hay)
        if part
    )


def match_score(label: str, prefix: str) -> float:
    """Higher is better: exact casefold match > prefix > word-start."""
    if not prefix:
        return 0.5
    needle = prefix.casefold()
    hay = label.casefold()
    if hay == needle:
        return 3.0
    if hay.startswith(needle):
        # Prefer shorter remaining suffix (closer match)
        return 2.0 + max(0.0, 1.0 - (len(hay) - len(needle)) / 40.0)
    import re

    for part in re.split(r"[\s.]+", hay):
        if part.startswith(needle):
            return 1.0
    return 0.0
