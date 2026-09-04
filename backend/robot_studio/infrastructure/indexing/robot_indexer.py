"""Robot Framework symbol extraction via robot.api.parsing."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import ClassVar
from uuid import UUID

from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import IndexedSymbol
from robot_studio.infrastructure.language.robot_parsing_worker import (
    document_symbols,
    extract_references,
    extract_settings_import_paths,
)

# Files a Resource / Variables import may point at (same set the FS indexer parses).
_IMPORT_TARGET_SUFFIXES = {".robot", ".resource", ".py", ".yaml", ".yml"}

_KIND_MAP = {
    "file": SymbolKind.FILE,
    "test_suite": SymbolKind.TEST_SUITE,
    "resource": SymbolKind.RESOURCE,
    "library": SymbolKind.LIBRARY,
    "setting": SymbolKind.SETTING,
    "variable": SymbolKind.VARIABLE,
    "keyword": SymbolKind.KEYWORD,
    "test_case": SymbolKind.TEST_CASE,
    "tag": SymbolKind.TAG,
    "documentation": SymbolKind.DOCUMENTATION,
}


def _sid(kind: str, file_path: Path, name: str, line: int) -> str:
    raw = f"{kind}:{file_path}:{name}:{line}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:24]


def imported_indexable_paths(path: Path) -> list[Path]:
    """Resolve on-disk ``Resource`` / ``Variables`` targets next to *path*.

    Used by incremental indexing so a suite that imports ``common.resource``
    also gets that file's variables/keywords into the symbol store — without
    expanding hover AST fallbacks.
    """
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        tokens = extract_settings_import_paths(text)
    except (OSError, ValueError):
        return []
    except Exception:  # noqa: BLE001 — robot.api may raise on broken source
        return []

    try:
        base = path.expanduser().resolve().parent
    except OSError:
        return []

    found: list[Path] = []
    seen: set[str] = set()
    for token in tokens:
        cleaned = token.strip().strip("'\"")
        if not cleaned:
            continue
        candidate = Path(cleaned).expanduser()
        if not candidate.is_file():
            candidate = base / cleaned
        try:
            if not candidate.is_file():
                continue
            resolved = candidate.resolve()
        except OSError:
            continue
        if resolved.suffix.lower() not in _IMPORT_TARGET_SUFFIXES:
            continue
        key = str(resolved)
        if key in seen:
            continue
        seen.add(key)
        found.append(resolved)
    return found


class RobotIndexer:
    """Extracts symbols from .robot / .resource files using robot.api.parsing."""

    INDEXABLE_SUFFIXES: ClassVar[set[str]] = {".robot", ".resource"}

    def index_file(
        self,
        path: Path,
        *,
        workspace_id: UUID | None,
        project_id: UUID | None,
    ) -> tuple[list[IndexedSymbol], list[dict]]:
        text = path.read_text(encoding="utf-8", errors="replace")
        mtime = path.stat().st_mtime
        parsed_symbols = document_symbols(text, str(path))
        raw_refs = extract_references(text, str(path))

        symbols: list[IndexedSymbol] = []
        symbol_ids: dict[tuple[str, str], str] = {}
        for item in parsed_symbols:
            kind_raw = str(item.get("kind") or "file")
            kind = _KIND_MAP.get(kind_raw, SymbolKind.FILE)
            name = str(item.get("name") or path.name)
            line = int(item.get("line") or 1)
            symbol_id = _sid(kind.value, path, name, line)
            symbol_ids[(kind.value, name.lower())] = symbol_id
            symbols.append(
                IndexedSymbol(
                    id=symbol_id,
                    name=name,
                    kind=kind.value,
                    file_path=path,
                    line=line,
                    project_id=project_id,
                    workspace_id=workspace_id,
                    documentation=str(item.get("documentation") or ""),
                    detail=str(item.get("detail") or ""),
                    last_modified=mtime,
                ),
            )

        references: list[dict] = []
        for ref in raw_refs:
            name = str(ref.get("name") or "")
            symbol_id = symbol_ids.get((SymbolKind.KEYWORD.value, name.lower()), "")
            if not symbol_id:
                symbol_id = symbol_ids.get((SymbolKind.TEST_CASE.value, name.lower()), "")
            references.append(
                {
                    "symbol_id": symbol_id,
                    "name": name,
                    "file_path": str(path),
                    "line": int(ref.get("line") or 1),
                    "project_id": str(project_id) if project_id else None,
                    "context": str(ref.get("context") or name)[:160],
                },
            )
        return symbols, references
