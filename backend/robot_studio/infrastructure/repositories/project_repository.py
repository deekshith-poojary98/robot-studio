"""SQLite-backed project registry and recent list."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import aiosqlite

from robot_studio.domain.interfaces.project import ProjectRepository
from robot_studio.domain.models import Project, ProjectType

RECENT_LIMIT_DEFAULT = 10


class SqliteProjectRepository(ProjectRepository):
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    async def initialize(self) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.executescript(
                """
                CREATE TABLE IF NOT EXISTS projects (
                    id TEXT PRIMARY KEY,
                    workspace_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    path TEXT NOT NULL UNIQUE,
                    type TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS recent_projects (
                    path TEXT PRIMARY KEY,
                    project_id TEXT NOT NULL,
                    workspace_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    type TEXT NOT NULL,
                    opened_at TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_projects_workspace
                    ON projects (workspace_id);

                CREATE INDEX IF NOT EXISTS idx_recent_projects_opened_at
                    ON recent_projects (opened_at DESC);
                """
            )
            await db.commit()

    async def create(self, project: Project) -> Project:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                INSERT INTO projects (id, workspace_id, name, path, type, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                    id = excluded.id,
                    workspace_id = excluded.workspace_id,
                    name = excluded.name,
                    type = excluded.type,
                    created_at = excluded.created_at
                """,
                (
                    str(project.id),
                    str(project.workspace_id),
                    project.name,
                    str(project.path.resolve()),
                    project.type.value,
                    project.created_at.isoformat(),
                ),
            )
            await db.commit()
        return project

    async def list_by_workspace(self, workspace_id: UUID) -> list[Project]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                """
                SELECT id, workspace_id, name, path, type, created_at
                FROM projects
                WHERE workspace_id = ?
                ORDER BY name
                """,
                (str(workspace_id),),
            )
            rows = await cursor.fetchall()
        return [self._row_to_project(row) for row in rows]

    async def get(self, project_id: UUID) -> Project | None:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                """
                SELECT id, workspace_id, name, path, type, created_at
                FROM projects
                WHERE id = ?
                """,
                (str(project_id),),
            )
            row = await cursor.fetchone()
        return self._row_to_project(row) if row else None

    async def get_by_path(self, path: str) -> Project | None:
        resolved = str(Path(path).expanduser().resolve())
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                """
                SELECT id, workspace_id, name, path, type, created_at
                FROM projects
                WHERE path = ?
                """,
                (resolved,),
            )
            row = await cursor.fetchone()
        return self._row_to_project(row) if row else None

    async def record_recent(self, project: Project) -> None:
        resolved = str(project.path.resolve())
        opened_at = datetime.now(UTC).isoformat()
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                "DELETE FROM recent_projects WHERE path = ?",
                (resolved,),
            )
            await db.execute(
                """
                INSERT INTO recent_projects
                    (path, project_id, workspace_id, name, type, opened_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    resolved,
                    str(project.id),
                    str(project.workspace_id),
                    project.name,
                    project.type.value,
                    opened_at,
                ),
            )
            await db.execute(
                """
                DELETE FROM recent_projects
                WHERE path NOT IN (
                    SELECT path FROM recent_projects
                    ORDER BY opened_at DESC
                    LIMIT ?
                )
                """,
                (RECENT_LIMIT_DEFAULT,),
            )
            await db.commit()

    async def list_recent(self, limit: int = RECENT_LIMIT_DEFAULT) -> list[Project]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                """
                SELECT
                    project_id AS id,
                    workspace_id,
                    name,
                    path,
                    type,
                    opened_at AS created_at
                FROM recent_projects
                ORDER BY opened_at DESC
                LIMIT ?
                """,
                (limit,),
            )
            rows = await cursor.fetchall()

        projects: list[Project] = []
        stale: list[str] = []
        for row in rows:
            path = Path(row["path"])
            if not path.is_dir():
                stale.append(row["path"])
                continue
            projects.append(self._row_to_project(row))

        if stale:
            async with aiosqlite.connect(self._database_path) as db:
                await db.executemany(
                    "DELETE FROM recent_projects WHERE path = ?",
                    [(path,) for path in stale],
                )
                await db.commit()

        return projects

    @staticmethod
    def _row_to_project(row: aiosqlite.Row) -> Project:
        created_raw = row["created_at"]
        created_at = datetime.fromisoformat(created_raw)
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=UTC)
        return Project(
            id=UUID(row["id"]),
            workspace_id=UUID(row["workspace_id"]),
            name=row["name"],
            path=Path(row["path"]),
            created_at=created_at,
            type=ProjectType(row["type"]),
        )
