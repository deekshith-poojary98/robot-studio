"""Tier 3 — Jedi-backed Python intelligence (stdlib, venv packages, imports).

Uses the active Robot environment's Python interpreter so completions reflect
installed packages (``requests``, ``robot.api``, etc.), not only the backend venv.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

try:
    import jedi
    from jedi import settings as jedi_settings
except ImportError:  # pragma: no cover - optional at import time
    jedi = None  # type: ignore[assignment,misc]
    jedi_settings = None  # type: ignore[assignment,misc]

_ENV_CACHE: dict[str, Any] = {}
_PROJECT_CACHE: dict[str, Any] = {}
_JEDI_CACHE_CONFIGURED = False

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
    _JEDI_CACHE_CONFIGURED = True


def _jedi_column(column: int) -> int:
    """Robot Studio uses 1-based columns; Jedi uses 0-based."""
    return max(0, column - 1)


def _map_kind(jedi_type: str) -> str:
    return _KIND_MAP.get(jedi_type, jedi_type or "variable")


def _get_environment(python_executable: Path) -> Any | None:
    if jedi is None:
        return None
    key = str(python_executable.expanduser().resolve())
    cached = _ENV_CACHE.get(key)
    if cached is not None:
        return cached
    try:
        env = jedi.create_environment(key, safe=False)
    except Exception:  # noqa: BLE001
        logger.debug("Jedi environment unavailable for %s", key, exc_info=True)
        return None
    _ENV_CACHE[key] = env
    return env


def _get_project(project_root: Path | None) -> Any | None:
    if jedi is None or project_root is None:
        return None
    key = str(project_root.expanduser().resolve())
    cached = _PROJECT_CACHE.get(key)
    if cached is not None:
        return cached
    try:
        project = jedi.Project(key)
    except Exception:  # noqa: BLE001
        logger.debug("Jedi project unavailable for %s", key, exc_info=True)
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
    environment = _get_environment(python_executable)
    if environment is None:
        return None
    try:
        return jedi.Script(
            content,
            path=file_path or "buffer.py",
            environment=environment,
            project=_get_project(project_root),
        )
    except Exception:  # noqa: BLE001
        logger.debug("Jedi Script creation failed", exc_info=True)
        return None


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
    except Exception:  # noqa: BLE001
        logger.debug("Jedi complete failed", exc_info=True)
        return []

    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in items:
        name = str(item.name or "")
        if not name:
            continue
        if name.startswith("_") and not (name.startswith("__") and name.endswith("__")):
            continue
        if prefix and not name.casefold().startswith(prefix.casefold()):
            continue
        if name in seen:
            continue
        seen.add(name)
        suffix = str(getattr(item, "complete", "") or "")
        insert_text = name + suffix
        doc = ""
        try:
            doc = str(item.docstring() or "")
        except Exception:  # noqa: BLE001
            doc = ""
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
                "documentation": doc,
                "insert_text": insert_text,
            },
        )
    return out


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
    except Exception:  # noqa: BLE001
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
    """Docs for the symbol under the caret."""
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return None
    try:
        names = script.infer(line, _jedi_column(column))
    except Exception:  # noqa: BLE001
        logger.debug("Jedi infer failed", exc_info=True)
        return None
    if not names:
        return None
    return _name_to_hover(names[0], fallback_path=file_path)


def jedi_definitions(
    content: str,
    file_path: str,
    line: int,
    column: int,
    python_executable: Path,
    project_root: Path | None,
) -> list[dict[str, Any]]:
    """Go-to-definition targets from Jedi."""
    script = _script(content, file_path, python_executable, project_root)
    if script is None:
        return []
    try:
        names = script.infer(line, _jedi_column(column))
    except Exception:  # noqa: BLE001
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
