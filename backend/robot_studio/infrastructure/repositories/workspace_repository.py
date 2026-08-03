"""SQLite-backed workspace registry and recent list."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import aiosqlite

from robot_studio.domain.interfaces.workspace import WorkspaceRepository
from robot_studio.domain.models import Workspace, WorkspaceSettings

RECENT_LIMIT_DEFAULT = 10


class SqliteWorkspaceRepository(WorkspaceRepository):
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    async def initialize(self) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.executescript(
                """
                CREATE TABLE IF NOT EXISTS workspaces (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    path TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS recent_workspaces (
                    path TEXT PRIMARY KEY,
                    workspace_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    opened_at TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_recent_opened_at
                    ON recent_workspaces (opened_at DESC);
                """
            )
            await db.commit()

    async def create(self, workspace: Workspace) -> Workspace:
        """Upsert by durable id; path is the current location only."""
        resolved = str(workspace.path.resolve())
        async with aiosqlite.connect(self._database_path) as db:
            # Drop any other identity that still claims this location.
            await db.execute(
                "DELETE FROM workspaces WHERE path = ? AND id != ?",
                (resolved, str(workspace.id)),
            )
            await db.execute(
                """
                INSERT INTO workspaces (id, name, path, created_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    path = excluded.path,
                    created_at = excluded.created_at
                """,
                (
                    str(workspace.id),
                    workspace.name,
                    resolved,
                    workspace.created_at.isoformat(),
                ),
            )
            # After a move/rename, recent must not keep the old path for this id.
            await db.execute(
                "DELETE FROM recent_workspaces WHERE workspace_id = ? AND path != ?",
                (str(workspace.id), resolved),
            )
            await db.commit()
        return workspace

    async def list_all(self) -> list[Workspace]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT id, name, path, created_at FROM workspaces ORDER BY name",
            )
            rows = await cursor.fetchall()
        return [self._row_to_workspace(row) for row in rows]

    async def get(self, workspace_id: UUID) -> Workspace | None:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT id, name, path, created_at FROM workspaces WHERE id = ?",
                (str(workspace_id),),
            )
            row = await cursor.fetchone()
        return self._row_to_workspace(row) if row else None

    async def get_by_path(self, path: Path) -> Workspace | None:
        resolved = str(path.resolve())
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT id, name, path, created_at FROM workspaces WHERE path = ?",
                (resolved,),
            )
            row = await cursor.fetchone()
        return self._row_to_workspace(row) if row else None

    async def record_recent(self, workspace: Workspace) -> None:
        resolved = str(workspace.path.resolve())
        opened_at = datetime.now(UTC).isoformat()

        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                "DELETE FROM recent_workspaces WHERE workspace_id = ?",
                (str(workspace.id),),
            )
            await db.execute(
                "DELETE FROM recent_workspaces WHERE path = ?",
                (resolved,),
            )
            await db.execute(
                """
                INSERT INTO recent_workspaces (path, workspace_id, name, opened_at)
                VALUES (?, ?, ?, ?)
                """,
                (resolved, str(workspace.id), workspace.name, opened_at),
            )
            await db.execute(
                """
                DELETE FROM recent_workspaces
                WHERE path NOT IN (
                    SELECT path FROM recent_workspaces
                    ORDER BY opened_at DESC
                    LIMIT ?
                )
                """,
                (RECENT_LIMIT_DEFAULT,),
            )
            await db.commit()

    async def list_recent(self, limit: int = RECENT_LIMIT_DEFAULT) -> list[Workspace]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                """
                SELECT workspace_id AS id, name, path, opened_at AS created_at
                FROM recent_workspaces
                ORDER BY opened_at DESC
                LIMIT ?
                """,
                (limit,),
            )
            rows = await cursor.fetchall()

        workspaces: list[Workspace] = []
        stale_paths: list[str] = []

        for row in rows:
            path = Path(row["path"])
            if not path.is_dir():
                stale_paths.append(row["path"])
                continue
            workspaces.append(self._row_to_workspace(row))

        if stale_paths:
            async with aiosqlite.connect(self._database_path) as db:
                await db.executemany(
                    "DELETE FROM recent_workspaces WHERE path = ?",
                    [(path,) for path in stale_paths],
                )
                await db.commit()

        return workspaces

    @staticmethod
    def _row_to_workspace(row: aiosqlite.Row) -> Workspace:
        created_raw = row["created_at"]
        created_at = datetime.fromisoformat(created_raw)
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=UTC)
        return Workspace(
            id=UUID(row["id"]),
            name=row["name"],
            path=Path(row["path"]),
            created_at=created_at,
            settings=WorkspaceSettings(),
        )
