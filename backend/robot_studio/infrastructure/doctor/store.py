"""SQLite persistence for Doctor report history."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import aiosqlite

from robot_studio.domain.models.doctor import (
    DoctorProfileId,
    DoctorReport,
    DoctorReportSummary,
)


class SqliteDoctorStore:
    def __init__(self, db_path: Path) -> None:
        self._db_path = db_path

    async def initialize(self) -> None:
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS doctor_reports (
                    id TEXT PRIMARY KEY,
                    project_id TEXT NOT NULL,
                    profile TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    graph_version TEXT NOT NULL DEFAULT '',
                    total_findings INTEGER NOT NULL DEFAULT 0,
                    critical_issues INTEGER NOT NULL DEFAULT 0,
                    providers_run TEXT NOT NULL DEFAULT '[]',
                    payload TEXT NOT NULL
                )
                """,
            )
            await db.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_doctor_reports_project
                ON doctor_reports(project_id, created_at DESC)
                """,
            )
            await db.commit()

    async def save_report(self, report: DoctorReport) -> None:
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                INSERT OR REPLACE INTO doctor_reports
                (id, project_id, profile, created_at, graph_version,
                 total_findings, critical_issues, providers_run, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    report.id,
                    report.project_id,
                    report.profile.value,
                    report.created_at.isoformat(),
                    report.graph_version,
                    report.summary.total_findings,
                    report.summary.critical_issues,
                    json.dumps(report.providers_run),
                    report.model_dump_json(),
                ),
            )
            await db.commit()

    async def get_report(self, report_id: str) -> DoctorReport | None:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                "SELECT payload FROM doctor_reports WHERE id = ?",
                (report_id,),
            ) as cur:
                row = await cur.fetchone()
        if row is None:
            return None
        return DoctorReport.model_validate_json(row["payload"])

    async def list_history(
        self,
        project_id: UUID,
        *,
        limit: int = 20,
    ) -> list[DoctorReportSummary]:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT id, project_id, profile, created_at, graph_version,
                       total_findings, critical_issues, providers_run
                FROM doctor_reports
                WHERE project_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (str(project_id), limit),
            ) as cur:
                rows = await cur.fetchall()
        out: list[DoctorReportSummary] = []
        for row in rows:
            created = datetime.fromisoformat(row["created_at"])
            if created.tzinfo is None:
                created = created.replace(tzinfo=UTC)
            out.append(
                DoctorReportSummary(
                    id=row["id"],
                    project_id=row["project_id"],
                    profile=DoctorProfileId(row["profile"]),
                    created_at=created,
                    graph_version=row["graph_version"] or "",
                    total_findings=int(row["total_findings"]),
                    critical_issues=int(row["critical_issues"]),
                    providers_run=json.loads(row["providers_run"] or "[]"),
                ),
            )
        return out

    async def latest_report(self, project_id: UUID) -> DoctorReport | None:
        history = await self.list_history(project_id, limit=1)
        if not history:
            return None
        return await self.get_report(history[0].id)
