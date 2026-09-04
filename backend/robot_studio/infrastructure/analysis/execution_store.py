"""SQLite persistence for execution knowledge linked to semantic entities."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import aiosqlite

from robot_studio.domain.models.analysis import BindingConfidence
from robot_studio.domain.models.execution_knowledge import (
    EntityExecutionStats,
    ExecutionEdgeKind,
    ExecutionEdgeRef,
    ExecutionHistoryEntry,
    ExecutionKnowledgeSnapshot,
    LinkedRunInfo,
)


class SqliteExecutionKnowledgeStore:
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    async def initialize(self) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.executescript(
                """
                CREATE TABLE IF NOT EXISTS execution_entity_stats (
                    entity_id TEXT NOT NULL,
                    project_id TEXT NOT NULL,
                    execution_count INTEGER NOT NULL DEFAULT 0,
                    pass_count INTEGER NOT NULL DEFAULT 0,
                    fail_count INTEGER NOT NULL DEFAULT 0,
                    skipped_count INTEGER NOT NULL DEFAULT 0,
                    average_duration_ms REAL NOT NULL DEFAULT 0,
                    total_duration_ms REAL NOT NULL DEFAULT 0,
                    last_execution TEXT,
                    last_failure TEXT,
                    first_seen TEXT,
                    last_seen TEXT,
                    PRIMARY KEY (entity_id, project_id)
                );

                CREATE INDEX IF NOT EXISTS idx_exec_stats_project
                    ON execution_entity_stats (project_id);

                CREATE TABLE IF NOT EXISTS execution_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id TEXT NOT NULL,
                    entity_id TEXT NOT NULL,
                    project_id TEXT NOT NULL,
                    status TEXT NOT NULL,
                    duration_ms REAL NOT NULL DEFAULT 0,
                    role TEXT NOT NULL DEFAULT 'subject',
                    executed_at TEXT,
                    message TEXT NOT NULL DEFAULT '',
                    graph_version TEXT NOT NULL DEFAULT '',
                    confidence TEXT NOT NULL DEFAULT 'high',
                    UNIQUE (run_id, entity_id, role)
                );

                CREATE INDEX IF NOT EXISTS idx_exec_history_entity
                    ON execution_history (project_id, entity_id, executed_at);
                CREATE INDEX IF NOT EXISTS idx_exec_history_run
                    ON execution_history (run_id);

                CREATE TABLE IF NOT EXISTS execution_edges (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    edge_kind TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    target_id TEXT,
                    run_id TEXT NOT NULL,
                    project_id TEXT NOT NULL,
                    target_name TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL DEFAULT '',
                    duration_ms REAL NOT NULL DEFAULT 0,
                    confidence TEXT NOT NULL DEFAULT 'high',
                    graph_version TEXT NOT NULL DEFAULT ''
                );

                CREATE INDEX IF NOT EXISTS idx_exec_edges_project
                    ON execution_edges (project_id, edge_kind);
                CREATE INDEX IF NOT EXISTS idx_exec_edges_source
                    ON execution_edges (source_id);
                CREATE INDEX IF NOT EXISTS idx_exec_edges_run
                    ON execution_edges (run_id);

                CREATE TABLE IF NOT EXISTS execution_linked_runs (
                    run_id TEXT PRIMARY KEY,
                    project_id TEXT NOT NULL,
                    graph_version TEXT NOT NULL,
                    incremental_revision INTEGER NOT NULL DEFAULT 0,
                    linked_at TEXT NOT NULL,
                    test_count INTEGER NOT NULL DEFAULT 0,
                    keyword_steps INTEGER NOT NULL DEFAULT 0
                );

                CREATE INDEX IF NOT EXISTS idx_exec_linked_project
                    ON execution_linked_runs (project_id, linked_at);
                """,
            )
            await db.commit()

    async def is_run_linked(self, run_id: UUID) -> bool:
        async with aiosqlite.connect(self._database_path) as db:
            cur = await db.execute(
                "SELECT 1 FROM execution_linked_runs WHERE run_id = ?",
                (str(run_id),),
            )
            return await cur.fetchone() is not None

    async def record_linked_run(self, info: LinkedRunInfo) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                INSERT INTO execution_linked_runs (
                    run_id, project_id, graph_version, incremental_revision,
                    linked_at, test_count, keyword_steps
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(run_id) DO UPDATE SET
                    graph_version=excluded.graph_version,
                    incremental_revision=excluded.incremental_revision,
                    linked_at=excluded.linked_at,
                    test_count=excluded.test_count,
                    keyword_steps=excluded.keyword_steps
                """,
                (
                    info.run_id,
                    info.project_id,
                    info.graph_version,
                    info.incremental_revision,
                    info.linked_at.isoformat(),
                    info.test_count,
                    info.keyword_steps,
                ),
            )
            await db.commit()

    async def upsert_history(self, entry: ExecutionHistoryEntry, project_id: str) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                INSERT INTO execution_history (
                    run_id, entity_id, project_id, status, duration_ms, role,
                    executed_at, message, graph_version, confidence
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(run_id, entity_id, role) DO UPDATE SET
                    status=excluded.status,
                    duration_ms=excluded.duration_ms,
                    executed_at=excluded.executed_at,
                    message=excluded.message,
                    graph_version=excluded.graph_version,
                    confidence=excluded.confidence
                """,
                (
                    entry.run_id,
                    entry.entity_id,
                    project_id,
                    entry.status,
                    entry.duration_ms,
                    entry.role,
                    entry.executed_at.isoformat() if entry.executed_at else None,
                    entry.message,
                    entry.graph_version,
                    entry.confidence.value,
                ),
            )
            await db.commit()

    async def add_edge(self, edge: ExecutionEdgeRef, project_id: str) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                INSERT INTO execution_edges (
                    edge_kind, source_id, target_id, run_id, project_id,
                    target_name, status, duration_ms, confidence, graph_version
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    edge.edge_kind.value,
                    edge.source_id,
                    edge.target_id,
                    edge.run_id,
                    project_id,
                    edge.target_name,
                    edge.status,
                    edge.duration_ms,
                    edge.confidence.value,
                    edge.graph_version,
                ),
            )
            await db.commit()

    async def apply_stat_delta(
        self,
        *,
        entity_id: str,
        project_id: str,
        status: str,
        duration_ms: float,
        executed_at: datetime | None,
    ) -> None:
        now = (executed_at or datetime.now(UTC)).isoformat()
        status_u = status.upper()
        pass_inc = 1 if status_u == "PASS" else 0
        fail_inc = 1 if status_u == "FAIL" else 0
        skip_inc = 1 if status_u == "SKIP" else 0
        async with aiosqlite.connect(self._database_path) as db:
            cur = await db.execute(
                """
                SELECT execution_count, pass_count, fail_count, skipped_count,
                       total_duration_ms, first_seen, last_failure
                FROM execution_entity_stats
                WHERE entity_id = ? AND project_id = ?
                """,
                (entity_id, project_id),
            )
            row = await cur.fetchone()
            if row is None:
                total = duration_ms
                count = 1
                avg = duration_ms
                await db.execute(
                    """
                    INSERT INTO execution_entity_stats (
                        entity_id, project_id, execution_count, pass_count, fail_count,
                        skipped_count, average_duration_ms, total_duration_ms,
                        last_execution, last_failure, first_seen, last_seen
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        entity_id,
                        project_id,
                        count,
                        pass_inc,
                        fail_inc,
                        skip_inc,
                        avg,
                        total,
                        now,
                        now if fail_inc else None,
                        now,
                        now,
                    ),
                )
            else:
                exec_count = int(row[0]) + 1
                pass_count = int(row[1]) + pass_inc
                fail_count = int(row[2]) + fail_inc
                skip_count = int(row[3]) + skip_inc
                total = float(row[4]) + duration_ms
                avg = total / exec_count if exec_count else 0.0
                first_seen = row[5] or now
                last_failure = now if fail_inc else row[6]
                await db.execute(
                    """
                    UPDATE execution_entity_stats SET
                        execution_count = ?,
                        pass_count = ?,
                        fail_count = ?,
                        skipped_count = ?,
                        average_duration_ms = ?,
                        total_duration_ms = ?,
                        last_execution = ?,
                        last_failure = ?,
                        first_seen = ?,
                        last_seen = ?
                    WHERE entity_id = ? AND project_id = ?
                    """,
                    (
                        exec_count,
                        pass_count,
                        fail_count,
                        skip_count,
                        avg,
                        total,
                        now,
                        last_failure,
                        first_seen,
                        now,
                        entity_id,
                        project_id,
                    ),
                )
            await db.commit()

    async def get_stats(
        self,
        project_id: UUID,
        *,
        entity_id: str | None = None,
    ) -> list[EntityExecutionStats]:
        clauses = ["project_id = ?"]
        params: list[object] = [str(project_id)]
        if entity_id:
            clauses.append("entity_id = ?")
            params.append(entity_id)
        sql = f"SELECT * FROM execution_entity_stats WHERE {' AND '.join(clauses)}"
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cur = await db.execute(sql, params)
            rows = await cur.fetchall()
        return [self._row_stats(r) for r in rows]

    def _row_stats(self, row: aiosqlite.Row) -> EntityExecutionStats:
        def _dt(val: str | None) -> datetime | None:
            return datetime.fromisoformat(val) if val else None

        return EntityExecutionStats(
            entity_id=row["entity_id"],
            project_id=row["project_id"],
            execution_count=int(row["execution_count"]),
            pass_count=int(row["pass_count"]),
            fail_count=int(row["fail_count"]),
            skipped_count=int(row["skipped_count"]),
            average_duration_ms=float(row["average_duration_ms"]),
            total_duration_ms=float(row["total_duration_ms"]),
            last_execution=_dt(row["last_execution"]),
            last_failure=_dt(row["last_failure"]),
            first_seen=_dt(row["first_seen"]),
            last_seen=_dt(row["last_seen"]),
        )

    async def history_for_entity(
        self,
        project_id: UUID,
        entity_id: str,
        *,
        limit: int = 50,
        role: str | None = "subject",
    ) -> list[ExecutionHistoryEntry]:
        clauses = ["project_id = ?", "entity_id = ?"]
        params: list[object] = [str(project_id), entity_id]
        if role:
            clauses.append("role = ?")
            params.append(role)
        params.append(limit)
        sql = f"""
            SELECT * FROM execution_history
            WHERE {' AND '.join(clauses)}
            ORDER BY executed_at DESC
            LIMIT ?
        """
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cur = await db.execute(sql, params)
            rows = await cur.fetchall()
        return [self._row_history(r) for r in rows]

    def _row_history(self, row: aiosqlite.Row) -> ExecutionHistoryEntry:
        return ExecutionHistoryEntry(
            run_id=row["run_id"],
            entity_id=row["entity_id"],
            status=row["status"],
            duration_ms=float(row["duration_ms"]),
            role=row["role"],
            executed_at=datetime.fromisoformat(row["executed_at"])
            if row["executed_at"]
            else None,
            message=row["message"] or "",
            graph_version=row["graph_version"] or "",
            confidence=BindingConfidence(row["confidence"] or "high"),
        )

    async def last_failures(
        self,
        project_id: UUID,
        *,
        limit: int = 50,
    ) -> list[ExecutionHistoryEntry]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cur = await db.execute(
                """
                SELECT * FROM execution_history
                WHERE project_id = ? AND status = 'FAIL' AND role = 'subject'
                ORDER BY executed_at DESC
                LIMIT ?
                """,
                (str(project_id), limit),
            )
            rows = await cur.fetchall()
        return [self._row_history(r) for r in rows]

    async def list_edges(
        self,
        project_id: UUID,
        *,
        edge_kind: str | None = None,
        run_id: str | None = None,
        source_id: str | None = None,
    ) -> list[ExecutionEdgeRef]:
        clauses = ["project_id = ?"]
        params: list[object] = [str(project_id)]
        if edge_kind:
            clauses.append("edge_kind = ?")
            params.append(edge_kind)
        if run_id:
            clauses.append("run_id = ?")
            params.append(run_id)
        if source_id:
            clauses.append("source_id = ?")
            params.append(source_id)
        sql = f"SELECT * FROM execution_edges WHERE {' AND '.join(clauses)}"
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cur = await db.execute(sql, params)
            rows = await cur.fetchall()
        return [
            ExecutionEdgeRef(
                edge_kind=ExecutionEdgeKind(row["edge_kind"]),
                source_id=row["source_id"],
                target_id=row["target_id"],
                run_id=row["run_id"],
                target_name=row["target_name"] or "",
                status=row["status"] or "",
                duration_ms=float(row["duration_ms"]),
                confidence=BindingConfidence(row["confidence"] or "high"),
                graph_version=row["graph_version"] or "",
            )
            for row in rows
        ]

    async def linked_runs(self, project_id: UUID) -> list[LinkedRunInfo]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cur = await db.execute(
                """
                SELECT * FROM execution_linked_runs
                WHERE project_id = ?
                ORDER BY linked_at DESC
                """,
                (str(project_id),),
            )
            rows = await cur.fetchall()
        return [
            LinkedRunInfo(
                run_id=row["run_id"],
                project_id=row["project_id"],
                graph_version=row["graph_version"],
                incremental_revision=int(row["incremental_revision"]),
                linked_at=datetime.fromisoformat(row["linked_at"]),
                test_count=int(row["test_count"]),
                keyword_steps=int(row["keyword_steps"]),
            )
            for row in rows
        ]

    async def snapshot(self, project_id: UUID) -> ExecutionKnowledgeSnapshot:
        pid = str(project_id)
        async with aiosqlite.connect(self._database_path) as db:
            cur = await db.execute(
                "SELECT COUNT(*) FROM execution_linked_runs WHERE project_id = ?",
                (pid,),
            )
            linked = int((await cur.fetchone())[0])
            cur = await db.execute(
                "SELECT COUNT(*) FROM execution_entity_stats WHERE project_id = ?",
                (pid,),
            )
            entities = int((await cur.fetchone())[0])
            cur = await db.execute(
                "SELECT COUNT(*) FROM execution_edges WHERE project_id = ?",
                (pid,),
            )
            edges = int((await cur.fetchone())[0])
        return ExecutionKnowledgeSnapshot(
            project_id=pid,
            linked_runs=linked,
            entities_with_stats=entities,
            execution_edges=edges,
        )

    async def delete_run(self, run_id: UUID) -> None:
        """Remove edges/history for a run. Stats are not rewound (documented debt)."""
        rid = str(run_id)
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute("DELETE FROM execution_edges WHERE run_id = ?", (rid,))
            await db.execute("DELETE FROM execution_history WHERE run_id = ?", (rid,))
            await db.execute("DELETE FROM execution_linked_runs WHERE run_id = ?", (rid,))
            await db.commit()
