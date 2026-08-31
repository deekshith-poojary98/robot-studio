"""Diagnostics for ``.py`` buffers — parser, pyflakes, and env imports.

Three layers, because they answer different questions:

* **Syntax** (parso, via Jedi) reports *every* parse error in the buffer rather
  than aborting at the first one like ``ast.parse``, so a typo on line 3 does not
  hide a second one on line 40.
* **Semantics** (pyflakes) catches the mistakes that actually cost time —
  undefined names, unused imports, shadowed definitions — without needing type
  inference or a configured type checker.
* **Environment** checks whether ``import`` / ``from`` targets exist in the
  active interpreter (stdlib, venv ``site-packages``, or the project tree),
  and whether names in ``from package import Name`` actually exist on that
  package. pyflakes treats ``import pandas`` as a valid binding even when
  pandas is not installed, and it does not inspect the package's members.

pyflakes and env-import checks need a parseable tree, so they only run once the
buffer is syntactically valid; while you are mid-edit you still get the syntax
layer.
"""

from __future__ import annotations

import ast
import logging
import sys
from pathlib import Path
from typing import Any

from robot_studio.infrastructure.language.python_jedi import (
    environment_sys_path,
    jedi_available,
    jedi_syntax_errors,
    jedi_unresolved_imported_names,
)

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

_SKIP_SITE_NAMES = {"__pycache__", "bin", "include"}
_IMPORT_ERROR_NAMES = frozenset({"ImportError", "ModuleNotFoundError"})

# python_executable → (site-packages mtimes, top-level module names)
_ENV_TOP_LEVEL_CACHE: dict[str, tuple[tuple[tuple[str, float], ...], frozenset[str]]] = {}


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
    if python_executable is not None:
        out.extend(
            _env_import_diagnostics(
                content,
                file_path,
                python_executable=python_executable,
                project_root=project_root,
            ),
        )
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


def _env_import_diagnostics(
    content: str,
    file_path: str,
    *,
    python_executable: Path,
    project_root: Path | None,
) -> list[dict[str, Any]]:
    """Missing packages and unknown ``from package import Name`` members."""
    try:
        tree = ast.parse(content, filename=file_path or "buffer.py")
    except (SyntaxError, ValueError, RecursionError):
        return []

    collector = _ImportCollector()
    collector.visit(tree)
    available = _env_top_level_modules(python_executable) | _local_top_level_modules(
        file_path,
        project_root,
    )
    out: list[dict[str, Any]] = []
    seen_packages: set[str] = set()
    for name, line, column in collector.imports:
        key = name.casefold()
        if key in seen_packages:
            continue
        seen_packages.add(key)
        if name in available:
            continue
        out.append(
            {
                "line": line,
                "column": column,
                "end_line": line,
                "end_column": column,
                "message": (
                    f"Cannot find package '{name}' in the active environment"
                ),
                "severity": "warning",
                "code": "missing_package",
                "source": "python",
            },
        )

    if jedi_available() and collector.from_names:
        probes = [
            (module, imported, line, column)
            for module, imported, line, column, top in collector.from_names
            if top is None or top in available
        ]
        unresolved = jedi_unresolved_imported_names(
            content,
            file_path,
            python_executable,
            project_root,
            probes,
        )
        for module, imported, line, column in unresolved:
            origin = module or "the package"
            out.append(
                {
                    "line": line,
                    "column": column,
                    "end_line": line,
                    "end_column": column,
                    "message": f"Cannot import name '{imported}' from '{origin}'",
                    "severity": "warning",
                    "code": "unresolved_import",
                    "source": "python",
                },
            )
    return out


class _ImportCollector(ast.NodeVisitor):
    """Collect top-level import names, skipping optional try/except ImportError."""

    def __init__(self) -> None:
        self.imports: list[tuple[str, int, int]] = []
        # module, imported name, line, 1-based column, top-level package or None if relative
        self.from_names: list[tuple[str, str, int, int, str | None]] = []

    def visit_Try(self, node: ast.Try) -> None:
        skip_body = _catches_import_error(node.handlers)
        if not skip_body:
            for child in node.body:
                self.visit(child)
        for handler in node.handlers:
            self.visit(handler)
        for child in node.orelse:
            self.visit(child)
        for child in node.finalbody:
            self.visit(child)

    def visit_Import(self, node: ast.Import) -> None:
        for alias in node.names:
            name = _top_level(alias.name)
            if not name:
                continue
            line = int(getattr(alias, "lineno", None) or node.lineno or 1)
            column = int(getattr(alias, "col_offset", None) or node.col_offset or 0) + 1
            self.imports.append((name, line, column))

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        relative = (node.level or 0) > 0
        top = _top_level(node.module) if not relative else None
        if not relative and top:
            line = int(node.lineno or 1)
            column = int(node.col_offset or 0) + 1
            self.imports.append((top, line, column))
        module = (node.module or "").strip()
        for alias in node.names:
            imported = (alias.name or "").strip()
            if not imported or imported == "*":
                continue
            line = int(getattr(alias, "lineno", None) or node.lineno or 1)
            column = int(getattr(alias, "col_offset", None) or node.col_offset or 0) + 1
            self.from_names.append((module, imported, line, column, top))


def _top_level(module: str | None) -> str:
    text = (module or "").strip()
    if not text or text == "*":
        return ""
    return text.split(".", 1)[0]


def _catches_import_error(handlers: list[ast.ExceptHandler]) -> bool:
    return any(_exception_names(handler.type) & _IMPORT_ERROR_NAMES for handler in handlers)


def _exception_names(node: ast.AST | None) -> set[str]:
    if node is None:
        return set()
    if isinstance(node, ast.Name):
        return {node.id}
    if isinstance(node, ast.Attribute):
        return {node.attr}
    if isinstance(node, ast.Tuple):
        names: set[str] = set()
        for elt in node.elts:
            names |= _exception_names(elt)
        return names
    return set()


def _env_top_level_modules(python_executable: Path) -> frozenset[str]:
    paths = environment_sys_path(python_executable)
    stamp: list[tuple[str, float]] = []
    for raw in paths:
        path = Path(raw)
        try:
            stamp.append((raw, path.stat().st_mtime))
        except OSError:
            stamp.append((raw, 0.0))
    key = str(python_executable)
    stamp_t = tuple(stamp)
    cached = _ENV_TOP_LEVEL_CACHE.get(key)
    if cached is not None and cached[0] == stamp_t:
        return cached[1]

    names: set[str] = set(sys.builtin_module_names)
    names.update(getattr(sys, "stdlib_module_names", ()))
    names.add("__future__")
    for raw in paths:
        names.update(_list_top_level(Path(raw)))
    frozen = frozenset(names)
    _ENV_TOP_LEVEL_CACHE[key] = (stamp_t, frozen)
    return frozen


def _local_top_level_modules(file_path: str, project_root: Path | None) -> set[str]:
    roots: list[Path] = []
    if file_path:
        parent = Path(file_path).expanduser().resolve().parent
        if parent.is_dir():
            roots.append(parent)
    if project_root is not None:
        root = project_root.expanduser().resolve()
        if root.is_dir() and root not in roots:
            roots.append(root)
    names: set[str] = set()
    for root in roots:
        names.update(_list_top_level(root))
    return names


def _list_top_level(root: Path) -> set[str]:
    names: set[str] = set()
    try:
        entries = root.iterdir()
    except OSError:
        return names
    for entry in entries:
        name = entry.name
        if name.startswith(".") or name in _SKIP_SITE_NAMES:
            continue
        if name.endswith((".dist-info", ".egg-info", ".pth", ".egg")):
            continue
        try:
            is_file = entry.is_file()
            is_dir = entry.is_dir()
        except OSError:
            continue
        if is_dir:
            names.add(name)
        elif is_file:
            stem = name.split(".", 1)[0]
            if stem and name.endswith((".py", ".pyi", ".pyc", ".pyd", ".so", ".pyw")):
                names.add(stem)
            elif ".so" in name or name.endswith(".pyd"):
                names.add(stem)
    return names


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
