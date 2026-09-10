"""Deterministic package name matching for Package Manager search.

Rank tiers (lower is better):

1. exact
2. prefix
3. substring

Name only — no fuzzy subsequence matching and no summary matching.
"""

from __future__ import annotations

import re
from typing import Any

# exact → prefix → substring → no match
_TIER_EXACT = 0
_TIER_PREFIX = 1
_TIER_SUBSTRING = 2

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
    ascending and get a stable exact > prefix > substring order.

    ``summary`` is accepted for API compatibility but ignored.
    """
    _ = summary
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
    return None


def rank_packages(
    packages: list[Any],
    query: str,
    *,
    name_attr: str = "name",
    summary_attr: str = "summary",
) -> list[Any]:
    """Filter *packages* to name matches and sort by :func:`package_match_key`.

    Accepts either objects with attributes or mapping-like dicts.
    """
    _ = summary_attr
    needle = query.strip()
    if not needle:
        return list(packages)

    scored: list[tuple[tuple[int, int, str], Any]] = []
    for item in packages:
        name = _field(item, name_attr)
        if not name:
            continue
        key = package_match_key(needle, str(name))
        if key is not None:
            scored.append((key, item))

    scored.sort(key=lambda pair: pair[0])
    return [item for _, item in scored]


def _field(item: Any, attr: str) -> Any:
    if isinstance(item, dict):
        return item.get(attr)
    return getattr(item, attr, None)
