"""Workspace filesystem discovery + incremental indexing orchestration helpers."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID

from robot_studio.infrastructure.indexing.python_indexer import PythonLibraryIndexer
from robot_studio.infrastructure.indexing.robot_indexer import RobotIndexer
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore


INDEXABLE_SUFFIXES = {".robot", ".resource", ".py"}


@dataclass
class FilesystemIndexer:
    store: SqliteIndexStore
    robot: RobotIndexer = field(default_factory=RobotIndexer)
    python: PythonLibraryIndexer = field(default_factory=PythonLibraryIndexer)

    def discover_files(self, root: Path) -> list[Path]:
        if not root.exists():
            return []
        found: list[Path] = []
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix.lower() not in INDEXABLE_SUFFIXES:
                continue
            # Skip virtualenvs and caches.
            parts = {part.lower() for part in path.parts}
            if parts & {"__pycache__", ".venv", "venv", "node_modules", ".git"}:
                continue
            if "Environments" in path.parts:
                continue
            found.append(path)
        return sorted(found)

    async def index_file(
        self,
        path: Path,
        *,
        workspace_id: UUID,
        project_id: UUID | None,
        force: bool = False,
    ) -> tuple[int, bool]:
        if not path.is_file():
            removed = await self.store.remove_file(path)
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
            symbols, references = self.robot.index_file(
                path,
                workspace_id=workspace_id,
                project_id=project_id,
            )
        elif suffix in PythonLibraryIndexer.INDEXABLE_SUFFIXES:
            symbols = self.python.index_file(
                path,
                workspace_id=workspace_id,
                project_id=project_id,
            )

        await self.store.upsert_symbols(symbols)
        if references:
            # Attach symbol_ids when definitions exist later via name match.
            await self.store.upsert_references(references)
        return len(symbols), True
