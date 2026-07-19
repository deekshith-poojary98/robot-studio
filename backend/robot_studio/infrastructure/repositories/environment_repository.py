"""SQLite-backed environment registry."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import aiosqlite

from robot_studio.domain.interfaces.environment import EnvironmentRepository
from robot_studio.domain.models import Environment


class SqliteEnvironmentRepository(EnvironmentRepository):
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    async def initialize(self) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.executescript(
                """
                CREATE TABLE IF NOT EXISTS environments (
                    id TEXT PRIMARY KEY,
                    workspace_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    path TEXT NOT NULL UNIQUE,
                    python_version TEXT NOT NULL,
                    python_executable TEXT NOT NULL,
                    pip_executable TEXT NOT NULL,
                    robot_executable TEXT,
                    created_at TEXT NOT NULL,
                    is_active INTEGER NOT NULL DEFAULT 0
                );

                CREATE INDEX IF NOT EXISTS idx_environments_workspace
                    ON environments (workspace_id);

                CREATE INDEX IF NOT EXISTS idx_environments_workspace_active
                    ON environments (workspace_id, is_active);
                """
            )
            await db.commit()

    async def create(self, environment: Environment) -> Environment:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                INSERT INTO environments (
                    id, workspace_id, name, path, python_version,
                    python_executable, pip_executable, robot_executable,
                    created_at, is_active
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                    id = excluded.id,
                    workspace_id = excluded.workspace_id,
                    name = excluded.name,
                    python_version = excluded.python_version,
                    python_executable = excluded.python_executable,
                    pip_executable = excluded.pip_executable,
                    robot_executable = excluded.robot_executable,
                    created_at = excluded.created_at,
                    is_active = excluded.is_active
                """,
                self._to_row(environment),
            )
            await db.commit()
        return environment

    async def update(self, environment: Environment) -> Environment:
        return await self.create(environment)

    async def list_by_workspace(self, workspace_id: UUID) -> list[Environment]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                """
                SELECT *
                FROM environments
                WHERE workspace_id = ?
                ORDER BY name
                """,
                (str(workspace_id),),
            )
            rows = await cursor.fetchall()
        return [self._row_to_environment(row) for row in rows]

    async def get(self, environment_id: UUID) -> Environment | None:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM environments WHERE id = ?",
                (str(environment_id),),
            )
            row = await cursor.fetchone()
        return self._row_to_environment(row) if row else None

    async def get_by_path(self, path: str) -> Environment | None:
        resolved = str(Path(path).expanduser().resolve())
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM environments WHERE path = ?",
                (resolved,),
            )
            row = await cursor.fetchone()
        return self._row_to_environment(row) if row else None

    async def set_active(self, workspace_id: UUID, environment_id: UUID) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                UPDATE environments
                SET is_active = 0
                WHERE workspace_id = ?
                """,
                (str(workspace_id),),
            )
            await db.execute(
                """
                UPDATE environments
                SET is_active = 1
                WHERE id = ? AND workspace_id = ?
                """,
                (str(environment_id), str(workspace_id)),
            )
            await db.commit()

    async def clear_active(self, workspace_id: UUID) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                UPDATE environments
                SET is_active = 0
                WHERE workspace_id = ?
                """,
                (str(workspace_id),),
            )
            await db.commit()

    async def delete(self, environment_id: UUID) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                "DELETE FROM environments WHERE id = ?",
                (str(environment_id),),
            )
            await db.commit()

    @staticmethod
    def _to_row(environment: Environment) -> tuple:
        return (
            str(environment.id),
            str(environment.workspace_id),
            environment.name,
            str(environment.path.resolve()),
            environment.python_version,
            str(environment.python_executable),
            str(environment.pip_executable),
            str(environment.robot_executable) if environment.robot_executable else None,
            environment.created_at.isoformat(),
            1 if environment.is_active else 0,
        )

    @staticmethod
    def _row_to_environment(row: aiosqlite.Row) -> Environment:
        created_raw = row["created_at"]
        created_at = datetime.fromisoformat(created_raw)
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=UTC)
        robot_raw = row["robot_executable"]
        return Environment(
            id=UUID(row["id"]),
            workspace_id=UUID(row["workspace_id"]),
            name=row["name"],
            path=Path(row["path"]),
            python_version=row["python_version"],
            python_executable=Path(row["python_executable"]),
            pip_executable=Path(row["pip_executable"]),
            robot_executable=Path(robot_raw) if robot_raw else None,
            created_at=created_at,
            is_active=bool(row["is_active"]),
        )
