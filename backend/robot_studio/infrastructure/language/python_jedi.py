"""Tier 3 — Jedi-backed Python intelligence (stdlib, venv packages, imports).

The active Robot environment's ``site-packages`` are handed to Jedi as extra
``sys.path`` entries so completions reflect installed packages (``requests``,
``robot.api``, …), not only the backend venv.

Resolution is deliberately **in-process** (``InterpreterEnvironment``). Jedi's
default ``create_environment`` spawns ``<python> jedi/.../subprocess/__main__.py``,
which cannot work in the packaged sidecar: PyInstaller keeps ``.py`` sources
inside the archive, so that script path does not exist on disk and every Jedi
call would silently return nothing.
"""

from __future__ import annotations

import logging
import warnings
from collections.abc import Callable
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# Completion names Jedi returns for ``object`` / ``tuple`` / ``list`` when it
# cannot see domain-specific attributes — not evidence that ``attr`` is wrong.
_GENERIC_COMPLETION_NAMES = frozenset(
    {
        "append",
        "clear",
        "copy",
        "count",
        "extend",
        "get",
        "index",
        "insert",
        "items",
        "keys",
        "pop",
        "remove",
        "reverse",
        "sort",
        "values",
    },
)

# ``str`` surface Jedi returns when the base type is unknown or mis-inferred.
_STRING_SURFACE_NAMES = frozenset(
    {
        "capitalize",
        "casefold",
        "center",
        "encode",
        "endswith",
        "expandtabs",
        "find",
        "format",
        "format_map",
        "isalnum",
        "isalpha",
        "isascii",
        "isdecimal",
        "isdigit",
        "isidentifier",
        "islower",
        "isnumeric",
        "isprintable",
        "isspace",
        "istitle",
        "isupper",
        "join",
        "ljust",
        "lower",
        "lstrip",
        "partition",
        "removeprefix",
        "removesuffix",
        "replace",
        "rfind",
        "rindex",
        "rjust",
        "rpartition",
        "rsplit",
        "rstrip",
        "split",
        "splitlines",
        "startswith",
        "strip",
        "swapcase",
        "title",
        "translate",
        "upper",
        "maketrans",
        "zfill",
    },
)

# ``datetime`` / ``date`` fields Jedi may not tie back to the attribute probe.
_DATETIME_ATTR_NAMES = frozenset(
    {
        "astimezone",
        "date",
        "day",
        "dst",
        "fold",
        "hour",
        "microsecond",
        "minute",
        "month",
        "second",
        "time",
        "timestamp",
        "timetuple",
        "tzinfo",
        "utcoffset",
        "utctimetuple",
        "weekday",
        "year",
    },
)

# Partial ``pathlib.Path`` completions when Jedi sees a path-like value but not
# the full API — skip known Path methods in that situation.
_PATHLIKE_ATTR_NAMES = frozenset(
    {
        "absolute",
        "chmod",
        "exists",
        "glob",
        "is_dir",
        "is_file",
        "is_symlink",
        "iterdir",
        "mkdir",
        "open",
        "read_bytes",
        "read_text",
        "rename",
        "resolve",
        "rmdir",
        "stat",
        "suffix",
        "touch",
        "unlink",
        "with_name",
        "with_suffix",
        "write_bytes",
        "write_text",
    },
)
_PATHLIKE_COMPLETION_MARKERS = frozenset(
    {
        "anchor",
        "as_posix",
        "as_uri",
        "drive",
        "full_match",
        "is_absolute",
        "is_relative_to",
        "is_reserved",
        "match",
        "name",
        "parent",
        "parents",
        "parts",
        "root",
        "stem",
        "with_segments",
        "with_stem",
    },
)

# Keyword names Jedi's stubs often omit even though the stdlib accepts them.
_INCOMPLETE_SIGNATURE_KEYWORDS = frozenset({"fold", "tzinfo"})

try:
    import jedi
    from jedi import settings as jedi_settings
    from jedi.api.environment import InterpreterEnvironment
except ImportError:  # pragma: no cover - optional at import time
    jedi = None  # type: ignore[assignment,misc]
    jedi_settings = None  # type: ignore[assignment,misc]
    InterpreterEnvironment = None  # type: ignore[assignment,misc]

_ENVIRONMENT: Any | None = None
_SYS_PATH_CACHE: dict[str, list[str]] = {}
_PROJECT_CACHE: dict[tuple[str, tuple[str, ...]], Any] = {}
_SCRIPT_CACHE: dict[tuple[str, str, tuple[str, ...]], Any] = {}
_JEDI_CACHE_CONFIGURED = False

# One refresh fires completion + signature + hover for the same buffer; caching
# the most recent Script means parsing that buffer once instead of three times.
_SCRIPT_CACHE_SIZE = 4

# ``docstring()`` forces inference per item and dominates request latency (~350ms
# for ~190 candidates vs ~0ms for names). Only the rows a user can actually read
# get docs; the rest are resolved on demand by hover.
_DOCSTRING_BUDGET = 15

_KIND_MAP = {
    "function": "function",
    "class": "class",
    "module": "module",
    "keyword": "keyword",
    "property": "property",
    "statement": "variable",
    "param": "parameter",
    "path": "file",
    "namespace": "module",
    "instance": "variable",
}


def jedi_available() -> bool:
    return jedi is not None


def _ensure_jedi_cache_dir() -> None:
    """Use a writable cache — stdlib paths are often read-only in packaged apps."""
    global _JEDI_CACHE_CONFIGURED
    if _JEDI_CACHE_CONFIGURED or jedi_settings is None:
        return
    cache = Path.home() / ".robot-studio" / "jedi-cache"
    try:
        cache.mkdir(parents=True, exist_ok=True)
        jedi_settings.cache_directory = str(cache)
    except OSError:
        logger.debug("Could not configure Jedi cache at %s", cache, exc_info=True)

    # parso warns once per module it fails to cache. With a read-only cache dir
    # that is one warning per stdlib file touched, which buries the real log.
    warnings.filterwarnings(
        "ignore",
        message="Tried to save a file to .*",
        category=Warning,
        module="parso.cache",
    )
    _JEDI_CACHE_CONFIGURED = True


def _jedi_column(column: int) -> int:
    """Robot Studio uses 1-based columns; Jedi uses 0-based."""
    return max(0, column - 1)


def _map_kind(jedi_type: str) -> str:
    return _KIND_MAP.get(jedi_type, jedi_type or "variable")


def _get_environment() -> Any | None:
    """In-process environment — never spawns a helper interpreter (see module docs)."""
    global _ENVIRONMENT
    if jedi is None or InterpreterEnvironment is None:
        return None
    if _ENVIRONMENT is None:
        try:
            _ENVIRONMENT = InterpreterEnvironment()
        except Exception:
            logger.debug("Jedi InterpreterEnvironment unavailable", exc_info=True)
            return None
    return _ENVIRONMENT


def environment_sys_path(python_executable: Path) -> list[str]:
    """``site-packages`` of the target interpreter, derived from the venv layout.

    Derived rather than probed: a subprocess per keystroke is not affordable, and
    the layout is fixed by PEP 405 (``lib/pythonX.Y/site-packages`` on POSIX,
    ``Lib/site-packages`` on Windows).
    """
    key = str(python_executable)
    cached = _SYS_PATH_CACHE.get(key)
    if cached is not None:
        return cached

    paths: list[str] = []
    try:
        # Not ``resolve()``: a venv's bin/python is a symlink to the base
        # interpreter, so resolving it walks out of the venv and finds the
        # *base* site-packages instead of the environment's own.
        base = python_executable.expanduser().absolute()
        roots = [base.parent.parent]
        resolved = base.resolve().parent.parent
        if resolved != roots[0]:
            roots.append(resolved)
        for root in roots:
            candidates = [
                root / "Lib" / "site-packages",
                *sorted((root / "lib").glob("python3*/site-packages")),
            ]
            for candidate in candidates:
                if candidate.is_dir():
                    path = str(candidate)
                    if path not in paths:
                        paths.append(path)
    except OSError:
        logger.debug("Could not derive sys.path for %s", python_executable, exc_info=True)

    _SYS_PATH_CACHE[key] = paths
    return paths


def _get_project(project_root: Path | None, extra_paths: tuple[str, ...]) -> Any | None:
    if jedi is None:
        return None
    root = str(project_root.expanduser().resolve()) if project_root else ""
    key = (root, extra_paths)
    cached = _PROJECT_CACHE.get(key)
    if cached is not None:
        return cached
    try:
        project = jedi.Project(
            root or str(Path.cwd()),
            added_sys_path=list(extra_paths),
        )
    except Exception:
        logger.debug("Jedi project unavailable for %s", root, exc_info=True)
        return None
    _PROJECT_CACHE[key] = project
    return project


def _script(
    content: str,
    file_path: str,
    python_executable: Path,
    project_root: Path | None,
) -> Any | None:
    if jedi is None:
        return None
    _ensure_jedi_cache_dir()
    environment = _get_environment()
    if environment is None:
        return None

    extra_paths = tuple(environment_sys_path(python_executable))
    cache_key = (file_path, content, extra_paths)
    cached = _SCRIPT_CACHE.get(cache_key)
    if cached is not None:
        return cached

    try:
        script = jedi.Script(
            content,
            path=file_path or "buffer.py",
            environment=environment,
            project=_get_project(project_root, extra_paths),
        )
    except Exception:
        logger.debug("Jedi Script creation failed", exc_info=True)
        return None

    if len(_SCRIPT_CACHE) >= _SCRIPT_CACHE_SIZE:
        _SCRIPT_CACHE.pop(next(iter(_SCRIPT_CACHE)))
    _SCRIPT_CACHE[cache_key] = script
    return script


def reset_caches() -> None:
    """Drop per-environment state (called when the active environment changes)."""
    _SYS_PATH_CACHE.clear()
    _PROJECT_CACHE.clear()
    _SCRIPT_CACHE.clear()


def jedi_completions(
    content: str,
    file_path: str,
    line: int,
    column: int,
    python_executable: Path,
    project_root: Path | None,
    *,
    prefix: str = "",
) -> list[dict[str, Any]]:
    """Completions from Jedi (stdlib + active environment site-packages)."""
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return []
    try:
        items = script.complete(line, _jedi_column(column))
    except Exception:
        logger.debug("Jedi complete failed", exc_info=True)
        return []

    # Private names are noise unless the user reached for them by typing ``_``.
    wants_private = prefix.startswith("_")

    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in items:
        name = str(item.name or "")
        if not name:
            continue
        if not wants_private and name.startswith("_") and not _is_dunder(name):
            continue
        if prefix and not name.casefold().startswith(prefix.casefold()):
            continue
        if name in seen:
            continue
        seen.add(name)
        detail = ""
        try:
            detail = str(getattr(item, "description", "") or "")
        except Exception:  # noqa: BLE001
            detail = ""
        out.append(
            {
                "label": name,
                "kind": _map_kind(str(item.type or "")),
                "detail": detail or _map_kind(str(item.type or "")),
                "documentation": "",
                # ``complete`` is a suffix for append-style UIs; we replace the
                # typed prefix with the full symbol name in the editor popup.
                "insert_text": name,
                "_jedi_item": item,
            },
        )

    for entry in out[:_DOCSTRING_BUDGET]:
        item = entry.pop("_jedi_item", None)
        if item is None:
            continue
        try:
            entry["documentation"] = str(item.docstring() or "")
        except Exception:  # noqa: BLE001
            entry["documentation"] = ""
    for entry in out:
        entry.pop("_jedi_item", None)
    return out


def _is_dunder(name: str) -> bool:
    return name.startswith("__") and name.endswith("__")


def jedi_signature_help(
    content: str,
    file_path: str,
    line: int,
    column: int,
    python_executable: Path,
    project_root: Path | None,
) -> dict[str, Any] | None:
    """Parameter hints for a call resolved via Jedi."""
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return None
    try:
        signatures = script.get_signatures(line, _jedi_column(column))
    except Exception:
        logger.debug("Jedi get_signatures failed", exc_info=True)
        return None
    if not signatures:
        return None

    sig = signatures[0]
    params: list[dict[str, Any]] = []
    for param in sig.params:
        label = str(param.to_string())
        default = _default_from_label(label)
        params.append(
            {
                "name": str(param.name or ""),
                "label": label,
                "default": default,
                "required": default == "" and "*" not in label,
                "kind": "keyword_only" if label.startswith("*") else "positional_or_keyword",
                "type_name": "",
                "documentation": str(getattr(param, "description", "") or ""),
            },
        )

    active = int(getattr(sig, "index", 0) or 0)
    if params:
        active = max(0, min(active, len(params) - 1))

    signature_text = str(sig.to_string())
    doc = ""
    try:
        doc = str(sig.docstring() or "")
    except Exception:  # noqa: BLE001
        doc = ""

    return {
        "keyword": str(sig.name or ""),
        "label": signature_text,
        "detail": signature_text,
        "documentation": doc,
        "parameters": params,
        "active_parameter": active,
        "source_type": "python",
        "library_name": "",
    }


def jedi_hover(
    content: str,
    file_path: str,
    line: int,
    column: int,
    python_executable: Path,
    project_root: Path | None,
) -> dict[str, Any] | None:
    """Docs for the symbol under the caret.

    ``help`` is Jedi's hover API (keywords, builtins, methods). ``infer`` fills
    in the type when ``help`` returns a name with no docstring — an assignment
    like ``x = "hello"`` otherwise looks empty.
    """
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return None
    col = _jedi_column(column)
    help_names = _jedi_names(lambda: script.help(line, col), "help")
    infer_names = _jedi_names(lambda: script.infer(line, col), "infer")
    names = help_names or infer_names
    if not names:
        return None
    payload = _name_to_hover(names[0], fallback_path=file_path)
    if payload.get("documentation"):
        return payload
    if infer_names:
        extra = _name_to_hover(infer_names[0], fallback_path=file_path)
        if extra.get("documentation"):
            payload["documentation"] = extra["documentation"]
            if extra.get("detail"):
                payload["detail"] = extra["detail"]
    return payload


def _jedi_names(fetch: Callable[[], Any], what: str) -> list[Any]:
    try:
        return list(fetch() or [])
    except Exception:
        logger.debug("Jedi %s failed", what, exc_info=True)
        return []


def jedi_definitions(
    content: str,
    file_path: str,
    line: int,
    column: int,
    python_executable: Path,
    project_root: Path | None,
) -> list[dict[str, Any]]:
    """Go-to-definition targets from Jedi.

    ``goto`` follows imports and aliases to where a name is *defined*; ``infer``
    resolves to its *type*, which lands on ``class str`` for a variable. Try goto
    first and keep infer as the fallback for expressions goto cannot name.
    """
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return []
    col = _jedi_column(column)
    names: list[Any] = []
    try:
        names = list(script.goto(line, col, follow_imports=True, follow_builtin_imports=True))
    except Exception:
        logger.debug("Jedi goto failed", exc_info=True)
    if not names:
        try:
            names = list(script.infer(line, col))
        except Exception:
            logger.debug("Jedi infer failed", exc_info=True)
            return []

    out: list[dict[str, Any]] = []
    seen: set[tuple[str, int, int]] = set()
    for name in names:
        payload = _name_to_definition(name, fallback_path=file_path)
        if payload is None:
            continue
        key = (
            str(payload.get("file_path") or ""),
            int(payload.get("line") or 0),
            hash(str(payload.get("name") or "")),
        )
        if key in seen:
            continue
        seen.add(key)
        out.append(payload)
    return out


def jedi_syntax_errors(
    content: str,
    file_path: str,
    python_executable: Path,
    project_root: Path | None,
) -> list[dict[str, Any]]:
    """Parser errors for the buffer — all of them, not just the first."""
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return []
    try:
        errors = script.get_syntax_errors()
    except Exception:
        logger.debug("Jedi get_syntax_errors failed", exc_info=True)
        return []

    out: list[dict[str, Any]] = []
    for error in errors:
        message = ""
        try:
            message = str(error.get_message() or "")
        except Exception:  # noqa: BLE001
            message = "Syntax error"
        out.append(
            {
                "line": int(getattr(error, "line", 1) or 1),
                "column": int(getattr(error, "column", 0) or 0) + 1,
                "end_line": int(getattr(error, "until_line", 0) or getattr(error, "line", 1) or 1),
                "end_column": int(getattr(error, "until_column", 0) or 0) + 1,
                "message": message,
                "severity": "error",
                "code": "syntax",
                "source": "python",
            },
        )
    return out


def jedi_unresolved_imported_names(
    content: str,
    file_path: str,
    python_executable: Path,
    project_root: Path | None,
    probes: list[tuple[str, str, int, int]],
) -> list[tuple[str, str, int, int]]:
    """Return ``from module import name`` rows Jedi cannot resolve.

    Each probe is ``(module, imported_name, line, column)`` with 1-based columns.
    Empty infer *and* goto means the name is not on that module. If Jedi cannot
    run, returns nothing — never a false positive.
    """
    if not probes:
        return []
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return []
    unresolved: list[tuple[str, str, int, int]] = []
    for module, imported, line, column in probes:
        col = _jedi_column(column)
        found: list[Any] = []
        try:
            found = list(script.infer(line, col) or [])
        except Exception:
            logger.debug("Jedi infer failed for import %s", imported, exc_info=True)
            continue
        if not found:
            try:
                found = list(
                    script.goto(
                        line,
                        col,
                        follow_imports=True,
                        follow_builtin_imports=True,
                    )
                    or [],
                )
            except Exception:
                logger.debug("Jedi goto failed for import %s", imported, exc_info=True)
                continue
        if not found:
            unresolved.append((module, imported, line, column))
    return unresolved


def jedi_unknown_attributes(
    content: str,
    file_path: str,
    python_executable: Path,
    project_root: Path | None,
    probes: list[tuple[int, int, str]],
) -> list[tuple[int, int, str]]:
    """Return ``obj.attr`` probes Jedi cannot resolve at runtime.

    Each probe is ``(line, column, attr)`` with a 1-based column at the start of
    the attribute name. Skips when completions are empty (unknown base type) or
    when ``infer`` / ``goto`` resolves the attribute (avoids false positives on
    loosely typed ``self`` fields and import aliases).
    """
    if not probes:
        return []
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return []
    unknown: list[tuple[int, int, str]] = []
    for line, column, attr in probes:
        if _jedi_attribute_resolved(script, line, column, attr):
            continue
        names = _jedi_attribute_completion_names(script, line, column, attr)
        if not names or attr in names or _completion_names_inconclusive(names, attr):
            continue
        unknown.append((line, column, attr))
    return unknown


def _jedi_attribute_resolved(script: Any, line: int, column: int, attr: str) -> bool:
    """True when infer/goto resolves anywhere on the attribute name."""
    start = _jedi_column(column)
    end = start + max(len(attr), 1)
    for col in range(start, end):
        try:
            if script.infer(line, col) or []:
                return True
        except Exception:
            logger.debug("Jedi infer failed for attribute %s", attr, exc_info=True)
        try:
            if script.goto(
                line,
                col,
                follow_imports=True,
                follow_builtin_imports=True,
            ):
                return True
        except Exception:
            logger.debug("Jedi goto failed for attribute %s", attr, exc_info=True)
    return False


def _jedi_attribute_completion_names(
    script: Any,
    line: int,
    column: int,
    attr: str,
) -> set[str]:
    """Completion names at the start of ``attr`` (where the name is fully typed)."""
    col = _jedi_column(column)
    try:
        completions = list(script.complete(line, col) or [])
    except Exception:
        logger.debug("Jedi complete failed for attribute %s", attr, exc_info=True)
        return set()
    return {
        str(item.name)
        for item in completions
        if getattr(item, "name", None)
    }


def _completion_names_inconclusive(names: set[str], attr: str) -> bool:
    """True when completions do not confidently disprove ``attr``."""
    public = {
        name
        for name in names
        if not (name.startswith("__") and name.endswith("__"))
    }
    if not public:
        return True
    if public <= (_GENERIC_COMPLETION_NAMES | _STRING_SURFACE_NAMES):
        return True
    if attr in _PATHLIKE_ATTR_NAMES and public & _PATHLIKE_COMPLETION_MARKERS:
        return True
    return attr in _DATETIME_ATTR_NAMES


def jedi_unexpected_call_keywords(
    content: str,
    file_path: str,
    python_executable: Path,
    project_root: Path | None,
    probes: list[tuple[int, int, str]],
) -> list[tuple[int, int, str]]:
    """Return named arguments that match none of Jedi's signatures.

    Each probe is ``(line, column, keyword_name)``. Calls whose signatures
    include ``**kwargs`` (or cannot be resolved) are left quiet.
    """
    if not probes:
        return []
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return []
    unexpected: list[tuple[int, int, str]] = []
    for line, column, name in probes:
        if name in _INCOMPLETE_SIGNATURE_KEYWORDS:
            continue
        try:
            signatures = list(script.get_signatures(line, _jedi_column(column)) or [])
        except Exception:
            logger.debug("Jedi signatures failed for keyword %s", name, exc_info=True)
            continue
        if not signatures:
            continue
        allowed: set[str] = set()
        absorbs_extras = False
        for sig in signatures:
            for param in getattr(sig, "params", []) or []:
                label = str(param.to_string() or "")
                pname = str(getattr(param, "name", "") or "")
                if label.startswith("**") or pname.startswith("**"):
                    absorbs_extras = True
                    break
                if pname and not pname.startswith("*"):
                    allowed.add(pname)
            if absorbs_extras:
                break
        if absorbs_extras or not allowed:
            continue
        if name not in allowed:
            unexpected.append((line, column, name))
    return unexpected


def jedi_references(
    content: str,
    file_path: str,
    line: int,
    column: int,
    python_executable: Path,
    project_root: Path | None,
) -> list[dict[str, Any]]:
    """Every usage of the symbol under the caret, across the project."""
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return []
    try:
        names = script.get_references(line, _jedi_column(column), include_builtins=False)
    except Exception:
        logger.debug("Jedi get_references failed", exc_info=True)
        return []

    out: list[dict[str, Any]] = []
    seen: set[tuple[str, int, int]] = set()
    for name in names:
        module_path = getattr(name, "module_path", None)
        path = str(module_path) if module_path else file_path
        ref_line = int(getattr(name, "line", 1) or 1)
        ref_column = int(getattr(name, "column", 0) or 0) + 1
        key = (path, ref_line, ref_column)
        if key in seen:
            continue
        seen.add(key)
        out.append(
            {
                "id": "",
                "name": str(getattr(name, "name", "") or ""),
                "kind": _map_kind(str(getattr(name, "type", "") or "")),
                "file_path": path,
                "line": ref_line,
                "column": ref_column,
                "detail": str(getattr(name, "description", "") or ""),
                "documentation": "",
            },
        )
    return out


def jedi_rename(
    content: str,
    file_path: str,
    line: int,
    column: int,
    python_executable: Path,
    project_root: Path | None,
    *,
    new_name: str,
) -> dict[str, Any] | None:
    """Project-wide rename as a per-file edit set (never written to disk here)."""
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return None
    try:
        refactoring = script.rename(line, _jedi_column(column), new_name=new_name)
    except Exception as exc:
        logger.debug("Jedi rename failed", exc_info=True)
        return {"error": str(exc), "files": []}

    files: list[dict[str, Any]] = []
    try:
        for path, new_code in refactoring.get_changed_files().items():
            files.append(
                {
                    "file_path": str(path),
                    "content": new_code.get_new_code(),
                },
            )
    except Exception as exc:
        logger.debug("Jedi rename diff failed", exc_info=True)
        return {"error": str(exc), "files": []}

    return {"error": "", "files": files}


def _name_to_hover(name: Any, *, fallback_path: str) -> dict[str, Any]:
    module_path = getattr(name, "module_path", None)
    path = str(module_path) if module_path else fallback_path
    doc = ""
    try:
        doc = str(name.docstring() or "")
    except Exception:  # noqa: BLE001
        doc = ""
    detail = str(getattr(name, "description", "") or "")
    return {
        "name": str(getattr(name, "name", "") or ""),
        "kind": _map_kind(str(getattr(name, "type", "") or "")),
        "file_path": path,
        "line": int(getattr(name, "line", 1) or 1),
        "documentation": doc,
        "detail": detail,
        "id": "",
        "detail_kind": "annotation",
    }


def _name_to_definition(name: Any, *, fallback_path: str) -> dict[str, Any] | None:
    symbol_name = str(getattr(name, "name", "") or "")
    if not symbol_name:
        return None
    module_path = getattr(name, "module_path", None)
    path = str(module_path) if module_path else fallback_path
    doc = ""
    try:
        doc = str(name.docstring() or "")
    except Exception:  # noqa: BLE001
        doc = ""
    detail = str(getattr(name, "description", "") or "")
    return {
        "id": "",
        "name": symbol_name,
        "kind": _map_kind(str(getattr(name, "type", "") or "")),
        "file_path": path,
        "line": int(getattr(name, "line", 1) or 1),
        "documentation": doc,
        "detail": detail,
    }


def _default_from_label(label: str) -> str:
    if "=" not in label:
        return ""
    return label.rsplit("=", 1)[-1].strip()
