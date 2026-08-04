"""Completion pipeline — runs context-filtered providers and ranks results."""

from __future__ import annotations

from dataclasses import dataclass, field

from robot_studio.domain.interfaces.completion import (
    CompletionCandidate,
    CompletionProvider,
    CompletionRequestContext,
)
from robot_studio.infrastructure.language.completion.ranking import merge_and_rank
from robot_studio.infrastructure.language.completion.usage_store import (
    SqliteCompletionUsageStore,
)


@dataclass
class CompletionPipeline:
    providers: list[CompletionProvider] = field(default_factory=list)
    usage_store: SqliteCompletionUsageStore | None = None

    async def complete(
        self,
        ctx: CompletionRequestContext,
        *,
        limit: int = 100,
    ) -> list[CompletionCandidate]:
        usage: dict[str, int] = {}
        if self.usage_store is not None and ctx.project_id:
            try:
                usage = await self.usage_store.usage_map(ctx.project_id)
            except Exception:  # noqa: BLE001
                usage = {}

        batches: list[list[CompletionCandidate]] = []
        for provider in self.providers:
            if not provider.accepts(ctx):
                continue
            try:
                batch = await provider.complete(ctx)
            except Exception:  # noqa: BLE001 — one provider must not break completion
                continue
            for item in batch:
                key = f"{item.kind}:{item.label.casefold()}"
                item.usage_count = usage.get(key, 0)
                if not item.base_priority:
                    item.base_priority = provider.base_priority
            batches.append(batch)

        return merge_and_rank(batches, limit=limit)
