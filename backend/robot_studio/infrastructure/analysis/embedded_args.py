"""Robot Framework embedded-argument keyword matching.

Uses RF's own ``EmbeddedArguments`` so Studio accepts the same names Robot
does (``Select ${n} items`` ↔ ``Select 5 items``), including custom
``${name:pattern}`` forms.
"""

from __future__ import annotations

from functools import lru_cache
from re import error as ReError

from robot.running.arguments import EmbeddedArguments


@lru_cache(maxsize=512)
def _parse_embedded(name: str) -> EmbeddedArguments | None:
    try:
        return EmbeddedArguments.from_name(name)
    except (ValueError, ReError):
        return None


def has_embedded_arguments(name: str) -> bool:
    return bool(name) and "${" in name and _parse_embedded(name) is not None


def embedded_argument_variables(name: str) -> tuple[str, ...]:
    """Variables RF injects into the keyword body (``${type}``, …)."""
    parsed = _parse_embedded(name)
    if parsed is None:
        return ()
    return tuple(f"${{{arg}}}" for arg in parsed.args if arg)


def matches_embedded_keyword(pattern: str, call: str) -> bool:
    """True when *call* is an RF embedded-argument expansion of *pattern*."""
    if not pattern or not call or "${" not in pattern:
        return False
    parsed = _parse_embedded(pattern)
    if parsed is None:
        return False
    try:
        return bool(parsed.matches(call))
    except (ValueError, ReError):
        return False
