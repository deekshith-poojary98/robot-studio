"""Rank and merge CompletionCandidate lists from multiple providers."""

from __future__ import annotations

from robot_studio.domain.interfaces.completion import CompletionCandidate


def rank_score(item: CompletionCandidate) -> float:
    """
    Composite score — higher wins.

    Usage and buffer frequency push frequently typed / accepted items up;
    match quality and provider priority break ties.
    """
    return (
        item.match_score * 100.0
        + float(item.usage_count) * 12.0
        + float(item.buffer_frequency) * 6.0
        + float(item.base_priority)
    )


def merge_and_rank(
    batches: list[list[CompletionCandidate]],
    *,
    limit: int = 100,
) -> list[CompletionCandidate]:
    """Deduplicate by kind+label (casefold), keep highest score, sort desc."""
    best: dict[str, CompletionCandidate] = {}
    for batch in batches:
        for item in batch:
            key = f"{item.kind}:{item.label.casefold()}"
            existing = best.get(key)
            if existing is None or rank_score(item) > rank_score(existing):
                best[key] = item
    ranked = sorted(best.values(), key=rank_score, reverse=True)
    return ranked[:limit]
