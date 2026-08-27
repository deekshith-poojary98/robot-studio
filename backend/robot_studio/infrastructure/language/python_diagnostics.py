"""Diagnostics for ``.py`` buffers — parser errors plus pyflakes checks.

Two layers, because they answer different questions:

* **Syntax** (parso, via Jedi) reports *every* parse error in the buffer rather
  than aborting at the first one like ``ast.parse``, so a typo on line 3 does not
  hide a second one on line 40.
* **Semantics** (pyflakes) catches the mistakes that actually cost time —
  undefined names, unused imports, shadowed definitions — without needing type
  inference or a configured type checker.

pyflakes needs a parseable tree, so it only runs once the buffer is syntactically
valid; while you are mid-edit you still get the syntax layer.
"""

from __future__ import annotations

import ast
import logging
from pathlib import Path
from typing import Any

from robot_studio.infrastructure.language.python_jedi import jedi_available, jedi_syntax_errors

logger = logging.getLogger(__name__)

try:
    from pyflakes import checker as pyflakes_checker
except ImportError:  # pragma: no cover - optional at import time
    pyflakes_checker = None  # type: ignore[assignment]

# pyflakes reports style-ish observations alongside real defects. These are the
# ones worth interrupting someone for; the rest stay out of the Problems panel.
_WARNING_TYPES = {
    "UnusedImport",
    "UnusedVariable",
    "UnusedAnnotation",
    "RedefinedWhileUnused",
    "ImportShadowedByLoopVar",
    "ImportStarUsed",
    "ImportStarUsage",
    "DuplicateArgument",
    "LateFutureImport",
    "IsLiteral",
    "FStringMissingPlaceholders",
}
_ERROR_TYPES = {
    "UndefinedName",
    "UndefinedLocal",
    "UndefinedExport",
    "ReturnOutsideFunction",
    "YieldOutsideFunction",
    "ContinueOutsideLoop",
    "BreakOutsideLoop",
    "TwoStarredExpressions",
    "AssertTuple",
    "RaiseNotImplemented",
}


def pyflakes_available() -> bool:
    return pyflakes_checker is not None


def python_diagnostics(
    content: str,
    file_path: str,
    *,
    python_executable: Path | None = None,
    project_root: Path | None = None,
) -> list[dict[str, Any]]:
    """Syntax + semantic diagnostics for one Python buffer."""
    if not content.strip():
        return []

    out: list[dict[str, Any]] = []
    syntax = _syntax_diagnostics(content, file_path, python_executable, project_root)
    out.extend(syntax)
    if syntax:
        # An unparseable buffer makes every pyflakes finding suspect (names look
        # undefined because their definition failed to parse).
        return _finalize(out, file_path)

    out.extend(_pyflakes_diagnostics(content, file_path))
    return _finalize(out, file_path)


def _syntax_diagnostics(
    content: str,
    file_path: str,
    python_executable: Path | None,
    project_root: Path | None,
) -> list[dict[str, Any]]:
    if jedi_available() and python_executable is not None:
        try:
            return jedi_syntax_errors(content, file_path, python_executable, project_root)
        except Exception:  # noqa: BLE001
            logger.debug("Jedi syntax errors failed for %s", file_path, exc_info=True)

    # Fallback: one error, but better than none when Jedi is unavailable.
    try:
        ast.parse(content)
    except SyntaxError as exc:
        return [
            {
                "line": int(exc.lineno or 1),
                "column": int(exc.offset or 1),
                "end_line": int(getattr(exc, "end_lineno", 0) or exc.lineno or 1),
                "end_column": int(getattr(exc, "end_offset", 0) or exc.offset or 1),
                "message": f"SyntaxError: {exc.msg}",
                "severity": "error",
                "code": "syntax",
                "source": "python",
            },
        ]
    except (ValueError, RecursionError):
        # Null bytes, absurd nesting — not something to surface as a diagnostic.
        return []
    return []


def _pyflakes_diagnostics(content: str, file_path: str) -> list[dict[str, Any]]:
    if pyflakes_checker is None:
        return []
    try:
        tree = ast.parse(content, filename=file_path or "buffer.py")
    except (SyntaxError, ValueError, RecursionError):
        return []

    try:
        result = pyflakes_checker.Checker(
            tree,
            filename=file_path or "buffer.py",
            withDoctest=False,
        )
    except Exception:  # noqa: BLE001 — pyflakes can trip on exotic trees
        logger.debug("pyflakes failed for %s", file_path, exc_info=True)
        return []

    out: list[dict[str, Any]] = []
    for message in result.messages:
        name = type(message).__name__
        if name in _ERROR_TYPES:
            severity = "error"
        elif name in _WARNING_TYPES:
            severity = "warning"
        else:
            continue
        try:
            text = str(message.message % message.message_args)
        except Exception:  # noqa: BLE001
            text = name
        line = int(getattr(message, "lineno", 1) or 1)
        column = int(getattr(message, "col", 0) or 0) + 1
        out.append(
            {
                "line": line,
                "column": column,
                "end_line": line,
                "end_column": column,
                "message": text,
                "severity": severity,
                "code": _snake_case(name),
                "source": "pyflakes",
            },
        )
    return out


def _finalize(items: list[dict[str, Any]], file_path: str) -> list[dict[str, Any]]:
    """Stamp the file path and order by position, as the Problems panel expects."""
    for item in items:
        item["file_path"] = file_path
    items.sort(key=lambda item: (int(item.get("line") or 1), int(item.get("column") or 1)))
    return items


def _snake_case(name: str) -> str:
    out: list[str] = []
    for index, char in enumerate(name):
        if char.isupper() and index > 0:
            out.append("_")
        out.append(char.lower())
    return "".join(out)
