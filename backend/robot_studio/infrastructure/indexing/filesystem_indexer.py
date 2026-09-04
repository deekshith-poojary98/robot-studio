"""Workspace filesystem discovery + incremental indexing orchestration helpers."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any
from uuid import UUID

from robot_studio.domain.models import IndexedSymbol
from robot_studio.infrastructure.indexing.python_indexer import PythonLibraryIndexer
from robot_studio.infrastructure.indexing.robot_indexer import (
    RobotIndexer,
    imported_indexable_paths,
)
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.indexing.yaml_variable_indexer import (
    YamlVariableIndexer,
)

if TYPE_CHECKING:
    from robot_studio.infrastructure.analysis.engine import RobotAnalysisEngine


INDEXABLE_SUFFIXES = {".robot", ".resource", ".py", ".yaml", ".yml"}

# Pruned during discovery — never descend (VS Code / JetBrains style excludes).
_SKIP_DIR_NAMES = {
    "__pycache__",
    ".venv",
    "venv",
    "env",
    "node_modules",
    ".git",
    ".hg",
    ".svn",
    ".tox",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".robotstudio",
    "Environments",  # legacy Studio env root
    "site-packages",
    "dist-packages",
}


@dataclass(frozen=True)
class ParsedIndexPayload:
    """Picklable parse result for bulk parallel indexing."""

    path: str
    mtime: float
    symbols: list[dict[str, Any]]
    references: list[dict[str, Any]]
    error: str | None = None


def parse_indexable_file(
    path_str: str,
    workspace_id: str | None,
    project_id: str | None,
) -> ParsedIndexPayload:
    """Parse one indexable file in a worker process (no SQLite / analysis).

    Top-level and picklable for ``ProcessPoolExecutor``.
    """
    path = Path(path_str)
    try:
        if not path.is_file():
            return ParsedIndexPayload(
                path=path_str,
                mtime=0.0,
                symbols=[],
                references=[],
                error="not a file",
            )
        ws = UUID(workspace_id) if workspace_id else None
        pid = UUID(project_id) if project_id else None
        suffix = path.suffix.lower()
        symbols: list[IndexedSymbol] = []
        references: list[dict] = []
        if suffix in RobotIndexer.INDEXABLE_SUFFIXES:
            symbols, references = RobotIndexer().index_file(
                path,
                workspace_id=ws,
                project_id=pid,
            )
        elif suffix in PythonLibraryIndexer.INDEXABLE_SUFFIXES:
            symbols = PythonLibraryIndexer().index_file(
                path,
                workspace_id=ws,
                project_id=pid,
            )
        elif suffix in YamlVariableIndexer.INDEXABLE_SUFFIXES:
            symbols, references = YamlVariableIndexer().index_file(
                path,
                workspace_id=ws,
                project_id=pid,
            )
        mtime = path.stat().st_mtime
        return ParsedIndexPayload(
            path=path_str,
            mtime=mtime,
            symbols=[s.model_dump(mode="json") for s in symbols],
            references=list(references),
            error=None,
        )
    except Exception as exc:  # noqa: BLE001
        return ParsedIndexPayload(
            path=path_str,
            mtime=0.0,
            symbols=[],
            references=[],
            error=str(exc),
        )


@dataclass
class FilesystemIndexer:
    store: SqliteIndexStore
    analysis_engine: RobotAnalysisEngine | None = None
    robot: RobotIndexer = field(default_factory=RobotIndexer)
    python: PythonLibraryIndexer = field(default_factory=PythonLibraryIndexer)
    yaml_vars: YamlVariableIndexer = field(default_factory=YamlVariableIndexer)
    # Project IDs that need binder finalize after a bulk (rebind=False) pass.
    pending_analysis_projects: set[UUID] = field(default_factory=set)

    def discover_files(self, root: Path) -> list[Path]:
        """Find indexable sources under *root*, pruning heavy directories early."""
        import os

        if not root.exists():
            return []
        found: list[Path] = []
        root = root.resolve()
        for dirpath, dirnames, filenames in os.walk(root, topdown=True):
            # Mutating dirnames in-place prevents os.walk from descending.
            dirnames[:] = [
                name
                for name in dirnames
                if name not in _SKIP_DIR_NAMES and name.lower() not in _SKIP_DIR_NAMES
            ]
            for name in filenames:
                path = Path(dirpath) / name
                if path.suffix.lower() in INDEXABLE_SUFFIXES:
                    found.append(path)
        return sorted(found)

    async def index_file(
        self,
        path: Path,
        *,
        workspace_id: UUID,
        project_id: UUID | None,
        force: bool = False,
        analysis_rebind: bool = True,
    ) -> tuple[int, bool]:
        count, changed = await self._index_file_once(
            path,
            workspace_id=workspace_id,
            project_id=project_id,
            force=force,
            analysis_rebind=analysis_rebind,
        )
        if changed:
            await self._index_imported_chain(
                path,
                workspace_id=workspace_id,
                project_id=project_id,
                analysis_rebind=analysis_rebind,
            )
        return count, changed

    async def _index_file_once(
        self,
        path: Path,
        *,
        workspace_id: UUID,
        project_id: UUID | None,
        force: bool = False,
        analysis_rebind: bool = True,
    ) -> tuple[int, bool]:
        if not path.is_file():
            removed = await self._remove_indexed_file(
                path,
                project_id=project_id,
                analysis_rebind=analysis_rebind,
            )
            return removed, False

        mtime = path.stat().st_mtime
        previous = await self.store.get_file_mtime(path)
        if not force and previous is not None and abs(previous - mtime) < 1e-6:
            return 0, False

        payload = await asyncio.to_thread(
            parse_indexable_file,
            str(path),
            str(workspace_id),
            str(project_id) if project_id else None,
        )
        if payload.error:
            raise RuntimeError(payload.error)
        return await self.commit_parsed_file(
            payload,
            workspace_id=workspace_id,
            project_id=project_id,
            analysis_rebind=analysis_rebind,
        )

    async def _index_imported_chain(
        self,
        path: Path,
        *,
        workspace_id: UUID,
        project_id: UUID | None,
        analysis_rebind: bool,
        seen: set[str] | None = None,
    ) -> None:
        """Index Resource / Variables targets so hover can use the symbol store."""
        if path.suffix.lower() not in RobotIndexer.INDEXABLE_SUFFIXES:
            return
        visited = seen if seen is not None else set()
        try:
            origin = str(path.expanduser().resolve())
        except OSError:
            return
        visited.add(origin)
        try:
            imports = await asyncio.to_thread(imported_indexable_paths, path)
        except Exception:  # noqa: BLE001 — never fail the primary file's index
            return
        for imported in imports:
            if self._skip_import_target(imported):
                continue
            try:
                key = str(imported.resolve())
            except OSError:
                continue
            if key in visited:
                continue
            visited.add(key)
            await self._index_file_once(
                imported,
                workspace_id=workspace_id,
                project_id=project_id,
                force=False,
                analysis_rebind=analysis_rebind,
            )
            await self._index_imported_chain(
                imported,
                workspace_id=workspace_id,
                project_id=project_id,
                analysis_rebind=analysis_rebind,
                seen=visited,
            )

    @staticmethod
    def _skip_import_target(path: Path) -> bool:
        return any(
            part in _SKIP_DIR_NAMES or part.lower() in _SKIP_DIR_NAMES
            for part in path.parts
        )

    async def commit_parsed_file(
        self,
        payload: ParsedIndexPayload,
        *,
        workspace_id: UUID,
        project_id: UUID | None,
        analysis_rebind: bool = True,
        clear_existing: bool = True,
    ) -> tuple[int, bool]:
        """Write a parsed payload to SQLite and optionally ingest analysis."""
        path = Path(payload.path)
        if payload.error == "not a file" or not path.is_file():
            removed = await self._remove_indexed_file(
                path,
                project_id=project_id,
                analysis_rebind=analysis_rebind,
            )
            return removed, False
        if payload.error:
            raise RuntimeError(payload.error)

        symbols = [IndexedSymbol.model_validate(item) for item in payload.symbols]
        references = list(payload.references)

        await self.store.replace_file_index(
            path,
            symbols,
            references,
            clear_existing=clear_existing,
        )

        suffix = path.suffix.lower()
        if self.analysis_engine is not None and suffix in {".robot", ".resource"}:
            await self.analysis_engine.ingest_file(
                path,
                workspace_id=workspace_id,
                project_id=project_id,
                rebind=analysis_rebind,
            )
            if project_id is not None and not analysis_rebind:
                self.pending_analysis_projects.add(project_id)

        return len(symbols), True

    async def _remove_indexed_file(
        self,
        path: Path,
        *,
        project_id: UUID | None,
        analysis_rebind: bool,
    ) -> int:
        removed = await self.store.remove_file(path)
        if self.analysis_engine is not None:
            await self.analysis_engine.remove_file(
                path,
                project_id=project_id,
                rebind=analysis_rebind,
            )
            if project_id is not None and not analysis_rebind:
                self.pending_analysis_projects.add(project_id)
        return removed

    async def finalize_analysis(self) -> None:
        """Rebind projects that were ingested with rebind=False during a bulk pass."""
        if self.analysis_engine is None:
            return
        pending = list(self.pending_analysis_projects)
        self.pending_analysis_projects.clear()
        for project_id in pending:
            await self.analysis_engine.finalize_project(project_id)
