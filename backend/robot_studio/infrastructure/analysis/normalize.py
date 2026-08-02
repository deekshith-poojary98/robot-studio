"""Robot Framework name normalization for the Analysis Engine.

Uses string transforms only (no structural parsing). AST extraction lives in
semantic_extractor.py via robot.api.parsing.
"""

from __future__ import annotations


def normalize_keyword_name(name: str) -> str:
    """RF-style keyword normalize: drop spaces/underscores, casefold."""
    return (name or "").replace(" ", "").replace("_", "").casefold()


def normalize_variable_name(name: str) -> str:
    """Normalize variable for matching — strip $@&% and braces.

    Extended variable syntax (``${obj.attr}``) keeps the base name before ``.``.
    """
    raw = (name or "").replace(" ", "").replace("_", "").casefold()
    if not raw:
        return raw
    if raw[0] in "$@&%":
        raw = raw[1:]
    raw = raw.removeprefix("{").removesuffix("}")
    if "." in raw:
        raw = raw.split(".", maxsplit=1)[0]
    return raw


def strip_library_prefix(name: str) -> str:
    """Return keyword part after optional Library.Prefix."""
    if "." not in (name or ""):
        return name or ""
    return name.split(".", maxsplit=1)[1]


def strip_bdd_prefix(normalized_name: str, prefixes: set[str] | None = None) -> str:
    """Remove English BDD prefixes from an already-normalized keyword name."""
    if prefixes is None:
        prefixes = {"given", "when", "then", "and", "but"}
    for prefix in prefixes:
        if normalized_name.startswith(prefix) and len(normalized_name) > len(prefix):
            return normalized_name[len(prefix) :]
    return normalized_name
