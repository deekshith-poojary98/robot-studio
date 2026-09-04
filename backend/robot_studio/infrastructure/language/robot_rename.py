"""Rewrite Robot keyword names in a buffer (definition + call cells)."""

from __future__ import annotations

import re

from robot_studio.infrastructure.analysis.normalize import (
    normalize_keyword_name,
    strip_library_prefix,
)
from robot_studio.infrastructure.language.robot_parsing_worker import (
    is_robot_cell_separator,
    split_robot_row,
)

_BDD_PREFIXES = ("Given ", "When ", "Then ", "And ", "But ")
_SETTING_KEYWORD_HEADS = frozenset(
    {
        "suite setup",
        "suite teardown",
        "test setup",
        "test teardown",
        "test template",
        "task setup",
        "task teardown",
        "task template",
    },
)


def is_robot_keyword_name(name: str) -> bool:
    text = (name or "").strip()
    if not text or "\n" in text or "\r" in text:
        return False
    return not text.startswith(("*", "#"))


def replace_keyword_name(content: str, old: str, new: str) -> str:
    """Replace RF-equivalent *old* keyword cells with *new* (preserves qualifiers)."""
    old_norm = normalize_keyword_name(old)
    new_name = (new or "").strip()
    if not old_norm or not new_name or old_norm == normalize_keyword_name(new_name):
        return content

    newline = "\r\n" if "\r\n" in content else "\n"
    had_trailing = content.endswith("\n")
    lines = content.splitlines()
    in_keywords = False
    out: list[str] = []
    changed = False
    for raw in lines:
        stripped = raw.strip()
        if stripped.startswith("*") and stripped.endswith("*"):
            label = stripped.strip("*").strip().casefold()
            in_keywords = label in {"keywords", "keyword"}
            out.append(raw)
            continue
        if not stripped or stripped.startswith("#"):
            out.append(raw)
            continue
        updated = _rewrite_line(raw, old_norm, new_name, in_keywords=in_keywords)
        if updated != raw:
            changed = True
        out.append(updated)
    if not changed:
        return content
    joined = newline.join(out)
    if had_trailing:
        joined = f"{joined}{newline}"
    return joined


def _rewrite_line(raw: str, old_norm: str, new_name: str, *, in_keywords: bool) -> str:
    cells = split_robot_row(raw)
    if not cells:
        return raw
    # Reconstruct with separators preserved. Odd tokens are separators.
    parts: list[str] = []
    cell_index = 0
    leading = bool(raw.startswith((" ", "\t")))
    for part in cells:
        if is_robot_cell_separator(part or ""):
            parts.append(part)
            continue
        if not part:
            continue
        is_keyword_cell = False
        if leading:
            # First non-empty cell is the keyword (or assignment target).
            if cell_index == 0 or cell_index == 1 and re.match(r"^[\$@&%]", _first_token(parts)):
                is_keyword_cell = True
        elif in_keywords and cell_index == 0 and not part.strip().startswith("["):
            is_keyword_cell = True
        elif (not leading) and cell_index == 1:
            head = _first_token(parts).strip().casefold()
            if head in _SETTING_KEYWORD_HEADS:
                is_keyword_cell = True
        rewritten = _rewrite_cell(part, old_norm, new_name) if is_keyword_cell else part
        parts.append(rewritten)
        cell_index += 1
    return "".join(parts)


def _first_token(parts: list[str]) -> str:
    for part in parts:
        if part and not is_robot_cell_separator(part):
            return part
    return ""


def _rewrite_cell(cell: str, old_norm: str, new_name: str) -> str:
    leading_ws = cell[: len(cell) - len(cell.lstrip(" \t"))]
    trailing_ws = cell[len(cell.rstrip(" \t")) :]
    token = cell.strip()
    if not token:
        return cell

    bdd = ""
    rest = token
    for prefix in _BDD_PREFIXES:
        if rest.lower().startswith(prefix.lower()):
            bdd = rest[: len(prefix)]
            rest = rest[len(prefix) :].lstrip()
            break

    qualifier = ""
    body = rest
    without_lib = strip_library_prefix(rest)
    if without_lib != rest:
        qualifier = rest[: len(rest) - len(without_lib)]
        body = without_lib

    if normalize_keyword_name(body) != old_norm:
        return cell
    rebuilt = f"{bdd}{qualifier}{new_name}"
    return f"{leading_ws}{rebuilt}{trailing_ws}"
