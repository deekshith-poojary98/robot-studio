"""Plain-text content search across a project tree."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable
from pathlib import Path
from uuid import UUID

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.application.services.settings_service import SettingsService
from robot_studio.core.config import settings as env_settings
from robot_studio.domain.interfaces.search import (
    ContentFileHits,
    ContentMatch,
    ContentSearchProvider,
    ContentSearchResult,
    SearchMatchEnclosing,
)
from robot_studio.infrastructure.indexing.filesystem_indexer import _SKIP_DIR_NAMES
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore

logger = logging.getLogger(__name__)


class ContentSearchValidationError(Exception):
    """Raised when content search cannot run."""


def parse_extensions(raw: str) -> frozenset[str]:
    parts = []
    for item in raw.split(","):
        cleaned = item.strip().lower()
        if not cleaned:
            continue
        if not cleaned.startswith("."):
            cleaned = f".{cleaned}"
        parts.append(cleaned)
    return frozenset(parts)


class ContentSearchService(ContentSearchProvider):
    """Filesystem text search — independent of Analysis Engine matching."""

    def __init__(
        self,
        context: WorkspaceContext,
        index_store: SqliteIndexStore | None = None,
        settings_service: SettingsService | None = None,
    ) -> None:
        self._context = context
        self._index_store = index_store
        self._settings_service = settings_service

    async def is_available(self) -> bool:
        return self._context.project is not None or self._context.workspace is not None

    async def search_content(
        self,
        query: str,
        *,
        root: Path | None = None,
        project_id: UUID | None = None,
        workspace_id: UUID | None = None,
        limit: int | None = None,
        context_lines: int | None = None,
        extensions: frozenset[str] | None = None,
        cancel_check: Callable[[], bool] | None = None,
    ) -> ContentSearchResult:
        needle = (query or "").strip()
        if not needle:
            return ContentSearchResult(
                query="",
                truncated=False,
                files_scanned=0,
                files=[],
            )

        search_root = root
        if search_root is None:
            project = self._context.project
            workspace = self._context.workspace
            if project is not None:
                search_root = Path(project.path)
                project_id = project_id or project.id
                workspace_id = workspace_id or project.workspace_id
            elif workspace is not None:
                search_root = Path(workspace.path)
                workspace_id = workspace_id or workspace.id
            else:
                raise ContentSearchValidationError(
                    "Open a project before searching file contents",
                )

        search_root = search_root.expanduser().resolve()
        if not search_root.is_dir():
            raise ContentSearchValidationError(
                f"Search root does not exist: '{search_root}'",
            )

        prefs = (
            self._settings_service.get()
            if self._settings_service is not None
            else None
        )
        if extensions is not None:
            ext = extensions
        elif prefs is not None:
            ext = frozenset(prefs.search.content_search_extensions)
        else:
            ext = parse_extensions(env_settings.content_search_extensions)
        max_matches = (
            limit if limit is not None else env_settings.content_search_max_matches
        )
        ctx = (
            context_lines
            if context_lines is not None
            else env_settings.content_search_context_lines
        )
        max_bytes = env_settings.content_search_max_file_bytes
        ignore = (
            frozenset(prefs.search.ignore_patterns)
            if prefs is not None
            else frozenset()
        )

        return await asyncio.to_thread(
            self._scan,
            needle,
            search_root,
            ext,
            max_matches,
            ctx,
            max_bytes,
            project_id,
            workspace_id,
            cancel_check,
            ignore,
        )

    def _scan(
        self,
        needle: str,
        root: Path,
        extensions: frozenset[str],
        max_matches: int,
        context_lines: int,
        max_bytes: int,
        project_id: UUID | None,
        workspace_id: UUID | None,
        cancel_check: Callable[[], bool] | None,
        ignore_patterns: frozenset[str] | None = None,
    ) -> ContentSearchResult:
        import os

        needle_lower = needle.lower()
        files_out: list[ContentFileHits] = []
        total_matches = 0
        files_scanned = 0
        truncated = False
        skip_dirs = set(_SKIP_DIR_NAMES)
        for pattern in ignore_patterns or ():
            cleaned = pattern.strip()
            if cleaned:
                skip_dirs.add(cleaned)
                skip_dirs.add(cleaned.lower())

        # Optional per-file symbol lines for enclosing decoration.
        symbols_by_file: dict[str, list[tuple[int, str, str]]] = {}

        for dirpath, dirnames, filenames in os.walk(root, topdown=True):
            if cancel_check is not None and cancel_check():
                truncated = True
                break
            dirnames[:] = [
                name
                for name in dirnames
                if name not in skip_dirs and name.lower() not in skip_dirs
            ]
            for name in filenames:
                if cancel_check is not None and cancel_check():
                    truncated = True
                    break
                path = Path(dirpath) / name
                if path.suffix.lower() not in extensions:
                    continue
                try:
                    if path.stat().st_size > max_bytes:
                        continue
                except OSError:
                    continue

                files_scanned += 1
                try:
                    text = path.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue

                lines = text.splitlines()
                file_matches: list[ContentMatch] = []
                resolved = str(path.resolve())
                for index, line_text in enumerate(lines):
                    lower = line_text.lower()
                    start = 0
                    while True:
                        found = lower.find(needle_lower, start)
                        if found < 0:
                            break
                        line_no = index + 1
                        before = lines[max(0, index - context_lines) : index]
                        after = lines[index + 1 : index + 1 + context_lines]
                        enclosing = self._enclosing_sync(
                            symbols_by_file,
                            resolved,
                            line_no,
                            project_id,
                        )
                        file_matches.append(
                            ContentMatch(
                                line=line_no,
                                column=found + 1,
                                text=line_text,
                                before=before,
                                after=after,
                                enclosing=enclosing,
                            ),
                        )
                        total_matches += 1
                        start = found + max(len(needle_lower), 1)
                        if total_matches >= max_matches:
                            truncated = True
                            break
                    if truncated:
                        break

                if file_matches:
                    files_out.append(
                        ContentFileHits(
                            path=resolved,
                            match_count=len(file_matches),
                            matches=file_matches,
                        ),
                    )
                if truncated:
                    break
            if truncated:
                break

        return ContentSearchResult(
            query=needle,
            truncated=truncated,
            files_scanned=files_scanned,
            files=files_out,
        )

    def _enclosing_sync(
        self,
        cache: dict[str, list[tuple[int, str, str]]],
        file_path: str,
        line: int,
        project_id: UUID | None,
    ) -> SearchMatchEnclosing | None:
        """Best-effort enclosing keyword/test/variable from the symbol index."""
        if self._index_store is None:
            return None
        if file_path not in cache:
            # Lazy load is async in store; skip sync decoration in thread path.
            # Decoration are applied in an async post-pass instead.
            cache[file_path] = []
            return None
        symbols = cache[file_path]
        best: tuple[int, str, str] | None = None
        for sym_line, kind, name in symbols:
            if sym_line <= line and (best is None or sym_line >= best[0]):
                best = (sym_line, kind, name)
        if best is None:
            return None
        return SearchMatchEnclosing(kind=best[1], name=best[2], line=best[0])

    async def decorate_with_index(
        self,
        result: ContentSearchResult,
        *,
        project_id: UUID | None,
    ) -> ContentSearchResult:
        """Attach enclosing symbol metadata using the index (presentation only)."""
        if self._index_store is None or not result.files:
            return result

        try:
            symbols = await self._index_store.search_symbols(
                "",
                project_id=project_id,
                limit=8000,
            )
        except Exception:  # noqa: BLE001
            logger.debug("Index decorate failed", exc_info=True)
            return result

        by_file: dict[str, list[tuple[int, str, str]]] = {}
        for item in symbols:
            kind = str(item.get("kind") or "")
            if kind not in {"keyword", "test_case", "variable", "test_suite"}:
                continue
            path = str(item.get("file_path") or "")
            if not path:
                continue
            by_file.setdefault(path, []).append(
                (
                    int(item.get("line") or 0),
                    kind,
                    str(item.get("name") or ""),
                ),
            )
        for path in by_file:
            by_file[path].sort(key=lambda item: item[0])

        decorated_files: list[ContentFileHits] = []
        for file_hits in result.files:
            file_syms = by_file.get(file_hits.path, [])
            new_matches: list[ContentMatch] = []
            for match in file_hits.matches:
                enclosing = None
                best: tuple[int, str, str] | None = None
                for sym_line, kind, name in file_syms:
                    if sym_line <= match.line and (
                        best is None or sym_line >= best[0]
                    ):
                        best = (sym_line, kind, name)
                    elif sym_line > match.line:
                        break
                if best is not None:
                    enclosing = SearchMatchEnclosing(
                        kind=best[1],
                        name=best[2],
                        line=best[0],
                    )
                new_matches.append(
                    ContentMatch(
                        line=match.line,
                        column=match.column,
                        text=match.text,
                        before=list(match.before),
                        after=list(match.after),
                        enclosing=enclosing,
                    ),
                )
            decorated_files.append(
                ContentFileHits(
                    path=file_hits.path,
                    match_count=file_hits.match_count,
                    matches=new_matches,
                ),
            )
        return ContentSearchResult(
            query=result.query,
            truncated=result.truncated,
            files_scanned=result.files_scanned,
            files=decorated_files,
        )
