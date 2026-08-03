"""SQLite-backed execution history."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import aiosqlite

from robot_studio.domain.models import ExecutionRun, ExecutionStatus

_EXTRA_COLUMNS = (
    ("environment_name", "TEXT NOT NULL DEFAULT ''"),
    ("robot_version", "TEXT"),
    ("total_tests", "INTEGER"),
    ("passed", "INTEGER"),
    ("failed", "INTEGER"),
    ("skipped", "INTEGER"),
)


class SqliteExecutionRepository:
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    async def initialize(self) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.executescript(
                """
                CREATE TABLE IF NOT EXISTS execution_runs (
                    id TEXT PRIMARY KEY,
                    workspace_id TEXT NOT NULL,
                    project_id TEXT NOT NULL,
                    environment_id TEXT NOT NULL,
                    project_name TEXT NOT NULL,
                    suite TEXT NOT NULL,
                    status TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    finished_at TEXT,
                    duration_ms INTEGER,
                    exit_code INTEGER,
                    command TEXT NOT NULL,
                    output_dir TEXT,
                    output_xml TEXT,
                    log_html TEXT,
                    report_html TEXT,
                    environment_name TEXT NOT NULL DEFAULT '',
                    robot_version TEXT,
                    total_tests INTEGER,
                    passed INTEGER,
                    failed INTEGER,
                    skipped INTEGER
                );

                CREATE INDEX IF NOT EXISTS idx_execution_workspace
                    ON execution_runs (workspace_id, started_at DESC);

                CREATE INDEX IF NOT EXISTS idx_execution_project
                    ON execution_runs (project_id, started_at DESC);
                """
            )
            for column, definition in _EXTRA_COLUMNS:
                try:
                    await db.execute(
                        f"ALTER TABLE execution_runs ADD COLUMN {column} {definition}",
                    )
                except aiosqlite.OperationalError:
                    # Column already exists on upgraded databases.
                    pass
            await db.commit()

    async def create(self, run: ExecutionRun) -> ExecutionRun:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                INSERT INTO execution_runs (
                    id, workspace_id, project_id, environment_id, project_name,
                    suite, status, started_at, finished_at, duration_ms, exit_code,
                    command, output_dir, output_xml, log_html, report_html,
                    environment_name, robot_version, total_tests, passed, failed, skipped
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                self._to_row(run),
            )
            await db.commit()
        return run

    async def update(self, run: ExecutionRun) -> ExecutionRun:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                UPDATE execution_runs SET
                    workspace_id = ?,
                    project_id = ?,
                    environment_id = ?,
                    project_name = ?,
                    suite = ?,
                    status = ?,
                    started_at = ?,
                    finished_at = ?,
                    duration_ms = ?,
                    exit_code = ?,
                    command = ?,
                    output_dir = ?,
                    output_xml = ?,
                    log_html = ?,
                    report_html = ?,
                    environment_name = ?,
                    robot_version = ?,
                    total_tests = ?,
                    passed = ?,
                    failed = ?,
                    skipped = ?
                WHERE id = ?
                """,
                (
                    str(run.workspace_id),
                    str(run.project_id),
                    str(run.environment_id),
                    run.project_name,
                    run.suite,
                    run.status.value,
                    run.started_at.isoformat(),
                    run.finished_at.isoformat() if run.finished_at else None,
                    run.duration_ms,
                    run.exit_code,
                    run.command,
                    str(run.output_dir) if run.output_dir else None,
                    str(run.output_xml) if run.output_xml else None,
                    str(run.log_html) if run.log_html else None,
                    str(run.report_html) if run.report_html else None,
                    run.environment_name,
                    run.robot_version,
                    run.total_tests,
                    run.passed,
                    run.failed,
                    run.skipped,
                    str(run.id),
                ),
            )
            await db.commit()
        return run

    async def get(self, run_id: UUID) -> ExecutionRun | None:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM execution_runs WHERE id = ?",
                (str(run_id),),
            )
            row = await cursor.fetchone()
        return self._row_to_run(row) if row else None

    async def delete(self, run_id: UUID) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                "DELETE FROM execution_runs WHERE id = ?",
                (str(run_id),),
            )
            await db.commit()

    async def delete_by_workspace(self, workspace_id: UUID) -> int:
        async with aiosqlite.connect(self._database_path) as db:
            cursor = await db.execute(
                "DELETE FROM execution_runs WHERE workspace_id = ?",
                (str(workspace_id),),
            )
            await db.commit()
            return int(cursor.rowcount or 0)

    async def list_by_workspace(
        self,
        workspace_id: UUID,
        *,
        limit: int = 50,
    ) -> list[ExecutionRun]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                """
                SELECT * FROM execution_runs
                WHERE workspace_id = ?
                ORDER BY started_at DESC
                LIMIT ?
                """,
                (str(workspace_id), limit),
            )
            rows = await cursor.fetchall()
        return [self._row_to_run(row) for row in rows]

    @staticmethod
    def _to_row(run: ExecutionRun) -> tuple:
        return (
            str(run.id),
            str(run.workspace_id),
            str(run.project_id),
            str(run.environment_id),
            run.project_name,
            run.suite,
            run.status.value,
            run.started_at.isoformat(),
            run.finished_at.isoformat() if run.finished_at else None,
            run.duration_ms,
            run.exit_code,
            run.command,
            str(run.output_dir) if run.output_dir else None,
            str(run.output_xml) if run.output_xml else None,
            str(run.log_html) if run.log_html else None,
            str(run.report_html) if run.report_html else None,
            run.environment_name,
            run.robot_version,
            run.total_tests,
            run.passed,
            run.failed,
            run.skipped,
        )

    @staticmethod
    def _row_to_run(row: aiosqlite.Row) -> ExecutionRun:
        started = datetime.fromisoformat(row["started_at"])
        if started.tzinfo is None:
            started = started.replace(tzinfo=UTC)
        finished = None
        if row["finished_at"]:
            finished = datetime.fromisoformat(row["finished_at"])
            if finished.tzinfo is None:
                finished = finished.replace(tzinfo=UTC)
        keys = set(row.keys())
        return ExecutionRun(
            id=UUID(row["id"]),
            workspace_id=UUID(row["workspace_id"]),
            project_id=UUID(row["project_id"]),
            environment_id=UUID(row["environment_id"]),
            project_name=row["project_name"],
            suite=row["suite"],
            status=ExecutionStatus(row["status"]),
            started_at=started,
            finished_at=finished,
            duration_ms=row["duration_ms"],
            exit_code=row["exit_code"],
            command=row["command"] or "",
            output_dir=Path(row["output_dir"]) if row["output_dir"] else None,
            output_xml=Path(row["output_xml"]) if row["output_xml"] else None,
            log_html=Path(row["log_html"]) if row["log_html"] else None,
            report_html=Path(row["report_html"]) if row["report_html"] else None,
            environment_name=row["environment_name"] if "environment_name" in keys else "",
            robot_version=row["robot_version"] if "robot_version" in keys else None,
            total_tests=row["total_tests"] if "total_tests" in keys else None,
            passed=row["passed"] if "passed" in keys else None,
            failed=row["failed"] if "failed" in keys else None,
            skipped=row["skipped"] if "skipped" in keys else None,
        )
