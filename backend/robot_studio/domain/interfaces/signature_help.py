"""Signature Help provider ports — discover KeywordMetadata, never format UI."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field

from robot_studio.domain.models.keyword_metadata import (
    KeywordMetadata,
    merge_keyword_metadata,
)


@dataclass(frozen=True)
class SignatureHelpRequestContext:
    file_path: str
    content: str
    line: int
    column: int
    keyword: str
    arguments: tuple[str, ...] = ()
    active_parameter_hint: int = 0
    project_id: str | None = None


class SignatureHelpProvider(ABC):
    """Discovers keyword metadata for a call site. Does not format for UI."""

    @property
    @abstractmethod
    def provider_id(self) -> str: ...

    @property
    def priority(self) -> int:
        """Higher runs first when collecting (does not imply exclusive win)."""
        return 50

    def accepts(self, ctx: SignatureHelpRequestContext) -> bool:
        return bool(ctx.keyword.strip())

    @abstractmethod
    async def resolve(self, ctx: SignatureHelpRequestContext) -> KeywordMetadata | None:
        ...


@dataclass
class SignatureHelpPipeline:
    """Composable discovery — all providers may contribute; results are merged."""

    providers: list[SignatureHelpProvider] = field(default_factory=list)

    async def resolve(self, ctx: SignatureHelpRequestContext) -> KeywordMetadata | None:
        contributions: list[KeywordMetadata] = []
        ordered = sorted(self.providers, key=lambda p: p.priority, reverse=True)
        for provider in ordered:
            if not provider.accepts(ctx):
                continue
            try:
                meta = await provider.resolve(ctx)
            except Exception:  # noqa: BLE001 — one provider must not break signature help
                continue
            if meta is not None and meta.name:
                contributions.append(meta)
        if not contributions:
            return None
        return merge_keyword_metadata(*contributions)
