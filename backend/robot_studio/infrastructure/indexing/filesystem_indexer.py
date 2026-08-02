"""Workspace filesystem discovery + incremental indexing orchestration helpers."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING
from uuid import UUID

from robot_studio.infrastructure.indexing.python_indexer import PythonLibraryIndexer
from robot_studio.infrastructure.indexing.robot_indexer import RobotIndexer
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore

if TYPE_CHECKING:
    from robot_studio.infrastructure.analysis.engine import RobotAnalysisEngine


INDEXABLE_SUFFIXES = {".robot", ".resource", ".py"}

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


@dataclass
class FilesystemIndexer:
    store: SqliteIndexStore
    analysis_engine: RobotAnalysisEngine | None = None
    robot: RobotIndexer = field(default_factory=RobotIndexer)
    python: PythonLibraryIndexer = field(default_factory=PythonLibraryIndexer)
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
        if not path.is_file():
            removed = await self.store.remove_file(path)
            if self.analysis_engine is not None:
                await self.analysis_engine.remove_file(path, project_id=project_id)
            return removed, False

        mtime = path.stat().st_mtime
        previous = await self.store.get_file_mtime(path)
        if not force and previous is not None and abs(previous - mtime) < 1e-6:
            return 0, False

        await self.store.remove_file(path)
        await self.store.clear_file_references(path)

        symbols = []
        references: list[dict] = []
        suffix = path.suffix.lower()
        if suffix in RobotIndexer.INDEXABLE_SUFFIXES:
            symbols, references = await asyncio.to_thread(
                lambda: self.robot.index_file(
                    path,
                    workspace_id=workspace_id,
                    project_id=project_id,
                ),
            )
        elif suffix in PythonLibraryIndexer.INDEXABLE_SUFFIXES:
            symbols = await asyncio.to_thread(
                lambda: self.python.index_file(
                    path,
                    workspace_id=workspace_id,
                    project_id=project_id,
                ),
            )

        await self.store.upsert_symbols(symbols)
        if references:
            # Attach symbol_ids when definitions exist later via name match.
            await self.store.upsert_references(references)

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

    async def finalize_analysis(self) -> None:
        """Rebind projects that were ingested with rebind=False during a bulk pass."""
        if self.analysis_engine is None:
            return
        pending = list(self.pending_analysis_projects)
        self.pending_analysis_projects.clear()
        for project_id in pending:
            await self.analysis_engine.finalize_project(project_id)
