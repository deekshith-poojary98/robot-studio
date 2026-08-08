"""Deterministic package name matching for Package Manager search.

Rank tiers (lower is better):

1. exact
2. prefix
3. substring
4. fuzzy (ordered subsequence)

Ties break on match position / span, then the package name. Fuzzy matching is
intentionally conservative: query must be at least two characters, every
character must appear in order, and no summary-only fuzzy matching.
"""

from __future__ import annotations

import re
from typing import Any

# exact → prefix → substring → fuzzy → summary substring → no match
_TIER_EXACT = 0
_TIER_PREFIX = 1
_TIER_SUBSTRING = 2
_TIER_FUZZY = 3
_TIER_SUMMARY = 4
_TIER_NONE = 9

_NORMALIZE_RE = re.compile(r"[-_.]+")


def normalize_package_name(name: str) -> str:
    """PEP 503-ish canonicalize for comparison (casefold + collapse separators)."""
    return _NORMALIZE_RE.sub("-", name.strip().casefold()).strip("-")


def package_match_key(
    query: str,
    name: str,
    *,
    summary: str | None = None,
) -> tuple[int, int, str] | None:
    """Return a sort key for *name* against *query*, or ``None`` if no match.

    The tuple is ``(tier, secondary, normalized_name)`` so callers can sort
    ascending and get a stable exact > prefix > substring > fuzzy order.
    """
    needle = query.strip()
    if not needle:
        return None

    q = normalize_package_name(needle)
    n = normalize_package_name(name)
    if not q or not n:
        return None

    if n == q:
        return (_TIER_EXACT, 0, n)
    if n.startswith(q):
        return (_TIER_PREFIX, len(n), n)
    idx = n.find(q)
    if idx >= 0:
        return (_TIER_SUBSTRING, idx, n)

    # Fuzzy: ordered subsequence only — never for single-character queries.
    if len(q) >= 2:
        span = _subsequence_span(q, n)
        if span is not None:
            return (_TIER_FUZZY, span, n)

    if summary:
        hay = summary.casefold()
        raw = needle.casefold()
        if raw in hay or q in normalize_package_name(summary):
            return (_TIER_SUMMARY, 0, n)

    return None


def rank_packages(
    packages: list[Any],
    query: str,
    *,
    name_attr: str = "name",
    summary_attr: str = "summary",
) -> list[Any]:
    """Filter *packages* to matches and sort by :func:`package_match_key`.

    Accepts either objects with attributes or mapping-like dicts.
    """
    needle = query.strip()
    if not needle:
        return list(packages)

    scored: list[tuple[tuple[int, int, str], Any]] = []
    for item in packages:
        name = _field(item, name_attr)
        if not name:
            continue
        summary = _field(item, summary_attr)
        key = package_match_key(
            needle,
            str(name),
            summary=None if summary is None else str(summary),
        )
        if key is not None:
            scored.append((key, item))

    scored.sort(key=lambda pair: pair[0])
    return [item for _, item in scored]


def _field(item: Any, attr: str) -> Any:
    if isinstance(item, dict):
        return item.get(attr)
    return getattr(item, attr, None)


def _subsequence_span(query: str, name: str) -> int | None:
    """Smallest window in *name* that covers *query* as an ordered subsequence."""
    qi = 0
    start = 0
    for index, char in enumerate(name):
        if char != query[qi]:
            continue
        if qi == 0:
            start = index
        qi += 1
        if qi == len(query):
            return index - start + 1
    return None
