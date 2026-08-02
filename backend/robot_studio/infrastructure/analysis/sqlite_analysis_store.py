"""SQLite persistence for the Robot Analysis Engine graphs."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import aiosqlite

from robot_studio.domain.interfaces.analysis import AnalysisStore
from robot_studio.domain.models.analysis import (
    BindingConfidence,
    EdgeKind,
    EntityKind,
    GraphVersion,
    SemanticEdge,
    SemanticEntity,
)


class SqliteAnalysisStore(AnalysisStore):
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    async def initialize(self) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.executescript(
                """
                CREATE TABLE IF NOT EXISTS analysis_entities (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    name TEXT NOT NULL,
                    name_normalized TEXT NOT NULL,
                    file_path TEXT NOT NULL,
                    line INTEGER NOT NULL DEFAULT 1,
                    column_no INTEGER NOT NULL DEFAULT 1,
                    documentation TEXT NOT NULL DEFAULT '',
                    detail TEXT NOT NULL DEFAULT '',
                    project_id TEXT,
                    workspace_id TEXT,
                    qualified_name TEXT NOT NULL DEFAULT '',
                    epoch INTEGER NOT NULL DEFAULT 0
                );

                CREATE INDEX IF NOT EXISTS idx_analysis_entities_project_kind
                    ON analysis_entities (project_id, kind);
                CREATE INDEX IF NOT EXISTS idx_analysis_entities_norm
                    ON analysis_entities (project_id, name_normalized, kind);
                CREATE INDEX IF NOT EXISTS idx_analysis_entities_file
                    ON analysis_entities (file_path);

                CREATE TABLE IF NOT EXISTS analysis_edges (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    edge_kind TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    target_id TEXT,
                    source_file TEXT NOT NULL,
                    source_line INTEGER NOT NULL DEFAULT 1,
                    source_column INTEGER NOT NULL DEFAULT 1,
                    target_name TEXT NOT NULL DEFAULT '',
                    target_name_normalized TEXT NOT NULL DEFAULT '',
                    confidence TEXT NOT NULL DEFAULT 'low',
                    project_id TEXT,
                    context TEXT NOT NULL DEFAULT '',
                    epoch INTEGER NOT NULL DEFAULT 0
                );

                CREATE INDEX IF NOT EXISTS idx_analysis_edges_project_kind
                    ON analysis_edges (project_id, edge_kind);
                CREATE INDEX IF NOT EXISTS idx_analysis_edges_source
                    ON analysis_edges (source_id);
                CREATE INDEX IF NOT EXISTS idx_analysis_edges_target
                    ON analysis_edges (target_id);
                CREATE INDEX IF NOT EXISTS idx_analysis_edges_file
                    ON analysis_edges (source_file);
                CREATE INDEX IF NOT EXISTS idx_analysis_edges_norm
                    ON analysis_edges (project_id, target_name_normalized);

                CREATE TABLE IF NOT EXISTS analysis_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS analysis_cache (
                    cache_key TEXT PRIMARY KEY,
                    project_id TEXT,
                    payload TEXT NOT NULL,
                    epoch INTEGER NOT NULL
                );
                """,
            )
            await db.commit()

    def _epoch_key(self, project_id: UUID | None) -> str:
        return f"epoch:{project_id}" if project_id else "epoch:global"

    def _version_key(self, project_id: UUID) -> str:
        return f"graph_version:{project_id}"

    def _timestamp_key(self, project_id: UUID) -> str:
        return f"timestamp:{project_id}"

    async def _get_meta(self, key: str) -> str | None:
        async with aiosqlite.connect(self._database_path) as db:
            cursor = await db.execute(
                "SELECT value FROM analysis_meta WHERE key = ?",
                (key,),
            )
            row = await cursor.fetchone()
        return str(row[0]) if row else None

    async def _set_meta(self, key: str, value: str) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                INSERT INTO analysis_meta (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                (key, value),
            )
            await db.commit()

    async def get_epoch(self, project_id: UUID | None = None) -> int:
        raw = await self._get_meta(self._epoch_key(project_id))
        return int(raw) if raw else 0

    async def get_graph_version(self, project_id: UUID) -> GraphVersion:
        revision = await self.get_epoch(project_id)
        graph_version = await self._get_meta(self._version_key(project_id)) or "0"
        ts_raw = await self._get_meta(self._timestamp_key(project_id))
        if ts_raw:
            timestamp = datetime.fromisoformat(ts_raw)
        else:
            timestamp = datetime.now(UTC)
        return GraphVersion(
            project_id=str(project_id),
            graph_version=graph_version,
            incremental_revision=revision,
            timestamp=timestamp,
            epoch=revision,
        )

    async def bump_revision(
        self,
        project_id: UUID,
        *,
        new_graph_version: bool = False,
    ) -> GraphVersion:
        current = await self.get_epoch(project_id)
        nxt = current + 1
        await self._set_meta(self._epoch_key(project_id), str(nxt))
        if new_graph_version or not await self._get_meta(self._version_key(project_id)):
            await self._set_meta(self._version_key(project_id), uuid4().hex[:12])
        now = datetime.now(UTC).isoformat()
        await self._set_meta(self._timestamp_key(project_id), now)
        await self.invalidate_cache(project_id)
        return await self.get_graph_version(project_id)

    async def clear_file(self, file_path: Path) -> None:
        path = str(file_path.resolve())
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute("DELETE FROM analysis_entities WHERE file_path = ?", (path,))
            await db.execute("DELETE FROM analysis_edges WHERE source_file = ?", (path,))
            await db.commit()

    async def clear_project(self, project_id: UUID) -> None:
        pid = str(project_id)
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute("DELETE FROM analysis_entities WHERE project_id = ?", (pid,))
            await db.execute("DELETE FROM analysis_edges WHERE project_id = ?", (pid,))
            await db.commit()
        await self.invalidate_cache(project_id)

    async def upsert_entities(self, entities: list[SemanticEntity], *, epoch: int) -> None:
        if not entities:
            return
        async with aiosqlite.connect(self._database_path) as db:
            for entity in entities:
                await db.execute(
                    """
                    INSERT INTO analysis_entities (
                        id, kind, name, name_normalized, file_path, line, column_no,
                        documentation, detail, project_id, workspace_id, qualified_name, epoch
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        kind=excluded.kind,
                        name=excluded.name,
                        name_normalized=excluded.name_normalized,
                        file_path=excluded.file_path,
                        line=excluded.line,
                        column_no=excluded.column_no,
                        documentation=excluded.documentation,
                        detail=excluded.detail,
                        project_id=excluded.project_id,
                        workspace_id=excluded.workspace_id,
                        qualified_name=excluded.qualified_name,
                        epoch=excluded.epoch
                    """,
                    (
                        entity.id,
                        entity.kind.value,
                        entity.name,
                        entity.name_normalized,
                        str(entity.file_path.resolve()),
                        entity.line,
                        entity.column,
                        entity.documentation,
                        entity.detail,
                        str(entity.project_id) if entity.project_id else None,
                        str(entity.workspace_id) if entity.workspace_id else None,
                        entity.qualified_name,
                        epoch,
                    ),
                )
            await db.commit()

    async def upsert_edges(self, edges: list[SemanticEdge], *, epoch: int) -> None:
        if not edges:
            return
        async with aiosqlite.connect(self._database_path) as db:
            for edge in edges:
                await db.execute(
                    """
                    INSERT INTO analysis_edges (
                        edge_kind, source_id, target_id, source_file, source_line,
                        source_column, target_name, target_name_normalized, confidence,
                        project_id, context, epoch
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        edge.edge_kind.value,
                        edge.source_id,
                        edge.target_id,
                        str(edge.source_file.resolve()),
                        edge.source_line,
                        edge.source_column,
                        edge.target_name,
                        edge.target_name_normalized,
                        edge.confidence.value,
                        str(edge.project_id) if edge.project_id else None,
                        edge.context,
                        epoch,
                    ),
                )
            await db.commit()

    async def replace_file_graph(
        self,
        file_path: Path,
        entities: list[SemanticEntity],
        edges: list[SemanticEdge],
        *,
        epoch: int,
    ) -> None:
        await self.clear_file(file_path)
        await self.upsert_entities(entities, epoch=epoch)
        await self.upsert_edges(edges, epoch=epoch)

    def _row_entity(self, row: aiosqlite.Row) -> SemanticEntity:
        return SemanticEntity(
            id=row["id"],
            kind=EntityKind(row["kind"]),
            name=row["name"],
            name_normalized=row["name_normalized"],
            file_path=Path(row["file_path"]),
            line=int(row["line"]),
            column=int(row["column_no"]),
            documentation=row["documentation"] or "",
            detail=row["detail"] or "",
            project_id=UUID(row["project_id"]) if row["project_id"] else None,
            workspace_id=UUID(row["workspace_id"]) if row["workspace_id"] else None,
            qualified_name=row["qualified_name"] or "",
        )

    def _row_edge(self, row: aiosqlite.Row) -> SemanticEdge:
        return SemanticEdge(
            id=int(row["id"]),
            edge_kind=EdgeKind(row["edge_kind"]),
            source_id=row["source_id"],
            target_id=row["target_id"],
            source_file=Path(row["source_file"]),
            source_line=int(row["source_line"]),
            source_column=int(row["source_column"]),
            target_name=row["target_name"] or "",
            target_name_normalized=row["target_name_normalized"] or "",
            confidence=BindingConfidence(row["confidence"]),
            project_id=UUID(row["project_id"]) if row["project_id"] else None,
            context=row["context"] or "",
        )

    async def list_entities(
        self,
        *,
        project_id: UUID | None = None,
        kind: str | None = None,
        name_normalized: str | None = None,
    ) -> list[SemanticEntity]:
        clauses = ["1=1"]
        params: list[object] = []
        if project_id:
            clauses.append("project_id = ?")
            params.append(str(project_id))
        if kind:
            clauses.append("kind = ?")
            params.append(kind)
        if name_normalized:
            clauses.append("name_normalized = ?")
            params.append(name_normalized)
        sql = f"SELECT * FROM analysis_entities WHERE {' AND '.join(clauses)}"
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(sql, params)
            rows = await cursor.fetchall()
        return [self._row_entity(row) for row in rows]

    async def get_entity(self, entity_id: str) -> SemanticEntity | None:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM analysis_entities WHERE id = ?",
                (entity_id,),
            )
            row = await cursor.fetchone()
        return self._row_entity(row) if row else None

    async def find_entities_by_normalized_name(
        self,
        name_normalized: str,
        *,
        project_id: UUID | None = None,
        kinds: list[str] | None = None,
    ) -> list[SemanticEntity]:
        clauses = ["name_normalized = ?"]
        params: list[object] = [name_normalized]
        if project_id:
            clauses.append("project_id = ?")
            params.append(str(project_id))
        if kinds:
            placeholders = ",".join("?" for _ in kinds)
            clauses.append(f"kind IN ({placeholders})")
            params.extend(kinds)
        sql = f"SELECT * FROM analysis_entities WHERE {' AND '.join(clauses)}"
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(sql, params)
            rows = await cursor.fetchall()
        return [self._row_entity(row) for row in rows]

    async def list_edges(
        self,
        *,
        project_id: UUID | None = None,
        edge_kind: str | None = None,
        source_id: str | None = None,
        target_id: str | None = None,
        unbound_only: bool = False,
    ) -> list[SemanticEdge]:
        clauses = ["1=1"]
        params: list[object] = []
        if project_id:
            clauses.append("project_id = ?")
            params.append(str(project_id))
        if edge_kind:
            clauses.append("edge_kind = ?")
            params.append(edge_kind)
        if source_id:
            clauses.append("source_id = ?")
            params.append(source_id)
        if target_id:
            clauses.append("target_id = ?")
            params.append(target_id)
        if unbound_only:
            clauses.append("(target_id IS NULL OR confidence = 'low')")
        sql = f"SELECT * FROM analysis_edges WHERE {' AND '.join(clauses)}"
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(sql, params)
            rows = await cursor.fetchall()
        return [self._row_edge(row) for row in rows]

    async def update_edge_binding(
        self,
        edge_id: int,
        *,
        target_id: str | None,
        confidence: str,
    ) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                UPDATE analysis_edges
                SET target_id = ?, confidence = ?
                WHERE id = ?
                """,
                (target_id, confidence, edge_id),
            )
            await db.commit()

    async def get_cache(self, cache_key: str) -> str | None:
        async with aiosqlite.connect(self._database_path) as db:
            cursor = await db.execute(
                "SELECT payload, epoch, project_id FROM analysis_cache WHERE cache_key = ?",
                (cache_key,),
            )
            row = await cursor.fetchone()
        if not row:
            return None
        payload, epoch, project_id = row[0], int(row[1]), row[2]
        current = await self.get_epoch(UUID(project_id) if project_id else None)
        if epoch != current:
            return None
        return str(payload)

    async def set_cache(
        self,
        cache_key: str,
        payload: str,
        *,
        epoch: int,
        project_id: str,
    ) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                INSERT INTO analysis_cache (cache_key, project_id, payload, epoch)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(cache_key) DO UPDATE SET
                    project_id=excluded.project_id,
                    payload=excluded.payload,
                    epoch=excluded.epoch
                """,
                (cache_key, project_id, payload, epoch),
            )
            await db.commit()

    async def invalidate_cache(self, project_id: UUID | None = None) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            if project_id:
                await db.execute(
                    "DELETE FROM analysis_cache WHERE project_id = ?",
                    (str(project_id),),
                )
            else:
                await db.execute("DELETE FROM analysis_cache")
            await db.commit()

    async def counts(self, project_id: UUID) -> dict[str, int]:
        pid = str(project_id)
        async with aiosqlite.connect(self._database_path) as db:
            cur = await db.execute(
                "SELECT COUNT(*) FROM analysis_entities WHERE project_id = ?",
                (pid,),
            )
            entities = int((await cur.fetchone())[0])
            cur = await db.execute(
                "SELECT COUNT(*) FROM analysis_edges WHERE project_id = ?",
                (pid,),
            )
            edges = int((await cur.fetchone())[0])
            cur = await db.execute(
                """
                SELECT COUNT(*) FROM analysis_edges
                WHERE project_id = ? AND edge_kind = 'calls' AND target_id IS NULL
                """,
                (pid,),
            )
            unbound = int((await cur.fetchone())[0])
        return {"entities": entities, "edges": edges, "unbound_calls": unbound}
