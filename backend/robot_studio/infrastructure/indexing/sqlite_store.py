"""SQLite-backed symbol IndexStore with fuzzy search."""

from __future__ import annotations

import hashlib
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import aiosqlite

from robot_studio.domain.interfaces.indexing import IndexScope, IndexStore, SymbolKind
from robot_studio.domain.models import IndexedSymbol


def _symbol_id(kind: str, file_path: Path, name: str, line: int) -> str:
    raw = f"{kind}:{file_path}:{name}:{line}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:24]


class SqliteIndexStore(IndexStore):
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    async def initialize(self) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.executescript(
                """
                CREATE TABLE IF NOT EXISTS index_symbols (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    name_lower TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    file_path TEXT NOT NULL,
                    line INTEGER NOT NULL DEFAULT 1,
                    project_id TEXT,
                    workspace_id TEXT,
                    documentation TEXT NOT NULL DEFAULT '',
                    detail TEXT NOT NULL DEFAULT '',
                    last_modified REAL,
                    indexed_at TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_symbols_name
                    ON index_symbols (name_lower);
                CREATE INDEX IF NOT EXISTS idx_symbols_kind
                    ON index_symbols (kind, name_lower);
                CREATE INDEX IF NOT EXISTS idx_symbols_file
                    ON index_symbols (file_path);
                CREATE INDEX IF NOT EXISTS idx_symbols_project
                    ON index_symbols (project_id, kind);
                CREATE INDEX IF NOT EXISTS idx_symbols_workspace
                    ON index_symbols (workspace_id, kind);

                CREATE TABLE IF NOT EXISTS index_files (
                    file_path TEXT PRIMARY KEY,
                    mtime REAL NOT NULL,
                    workspace_id TEXT,
                    project_id TEXT,
                    indexed_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS index_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS index_references (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    name_lower TEXT NOT NULL,
                    file_path TEXT NOT NULL,
                    line INTEGER NOT NULL DEFAULT 1,
                    project_id TEXT,
                    context TEXT NOT NULL DEFAULT ''
                );

                CREATE INDEX IF NOT EXISTS idx_refs_symbol
                    ON index_references (symbol_id);
                CREATE INDEX IF NOT EXISTS idx_refs_name
                    ON index_references (name_lower);
                """
            )
            await db.commit()

    async def invalidate(self, scope: IndexScope, scope_id: str | None = None) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            if scope == IndexScope.WORKSPACE:
                if scope_id:
                    await db.execute(
                        "DELETE FROM index_symbols WHERE workspace_id = ?",
                        (scope_id,),
                    )
                    await db.execute(
                        "DELETE FROM index_files WHERE workspace_id = ?",
                        (scope_id,),
                    )
                    await db.execute(
                        "DELETE FROM index_references WHERE project_id IN "
                        "(SELECT DISTINCT project_id FROM index_symbols WHERE workspace_id = ?)",
                        (scope_id,),
                    )
                else:
                    await db.execute("DELETE FROM index_symbols")
                    await db.execute("DELETE FROM index_files")
                    await db.execute("DELETE FROM index_references")
            elif scope == IndexScope.PROJECT and scope_id:
                await db.execute(
                    "DELETE FROM index_symbols WHERE project_id = ?",
                    (scope_id,),
                )
                await db.execute(
                    "DELETE FROM index_files WHERE project_id = ?",
                    (scope_id,),
                )
                await db.execute(
                    "DELETE FROM index_references WHERE project_id = ?",
                    (scope_id,),
                )
            elif scope == IndexScope.FILE and scope_id:
                await db.execute(
                    "DELETE FROM index_symbols WHERE file_path = ?",
                    (scope_id,),
                )
                await db.execute(
                    "DELETE FROM index_files WHERE file_path = ?",
                    (scope_id,),
                )
                await db.execute(
                    "DELETE FROM index_references WHERE file_path = ?",
                    (scope_id,),
                )
            await db.commit()

    async def upsert_symbols(self, symbols: list) -> None:
        if not symbols:
            return
        now = datetime.now(UTC).isoformat()
        async with aiosqlite.connect(self._database_path) as db:
            files: dict[str, tuple[float | None, str | None, str | None]] = {}
            for item in symbols:
                symbol = item if isinstance(item, IndexedSymbol) else IndexedSymbol.model_validate(item)
                symbol_id = symbol.id or _symbol_id(
                    symbol.kind,
                    symbol.file_path,
                    symbol.name,
                    symbol.line,
                )
                await db.execute(
                    """
                    INSERT INTO index_symbols (
                        id, name, name_lower, kind, file_path, line, project_id,
                        workspace_id, documentation, detail, last_modified, indexed_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        name_lower = excluded.name_lower,
                        kind = excluded.kind,
                        file_path = excluded.file_path,
                        line = excluded.line,
                        project_id = excluded.project_id,
                        workspace_id = excluded.workspace_id,
                        documentation = excluded.documentation,
                        detail = excluded.detail,
                        last_modified = excluded.last_modified,
                        indexed_at = excluded.indexed_at
                    """,
                    (
                        symbol_id,
                        symbol.name,
                        symbol.name.lower(),
                        symbol.kind,
                        str(symbol.file_path),
                        symbol.line,
                        str(symbol.project_id) if symbol.project_id else None,
                        str(symbol.workspace_id) if symbol.workspace_id else None,
                        symbol.documentation,
                        symbol.detail,
                        symbol.last_modified,
                        now,
                    ),
                )
                files[str(symbol.file_path)] = (
                    symbol.last_modified,
                    str(symbol.workspace_id) if symbol.workspace_id else None,
                    str(symbol.project_id) if symbol.project_id else None,
                )
            for file_path, (mtime, workspace_id, project_id) in files.items():
                await db.execute(
                    """
                    INSERT INTO index_files (file_path, mtime, workspace_id, project_id, indexed_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(file_path) DO UPDATE SET
                        mtime = excluded.mtime,
                        workspace_id = excluded.workspace_id,
                        project_id = excluded.project_id,
                        indexed_at = excluded.indexed_at
                    """,
                    (file_path, mtime or 0.0, workspace_id, project_id, now),
                )
            await db.execute(
                """
                INSERT INTO index_meta (key, value) VALUES ('last_indexed_at', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                (now,),
            )
            await db.commit()

    async def upsert_references(self, references: list[dict]) -> None:
        if not references:
            return
        async with aiosqlite.connect(self._database_path) as db:
            for ref in references:
                await db.execute(
                    """
                    INSERT INTO index_references (
                        symbol_id, name, name_lower, file_path, line, project_id, context
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        ref.get("symbol_id") or "",
                        ref["name"],
                        ref["name"].lower(),
                        str(ref["file_path"]),
                        int(ref.get("line") or 1),
                        str(ref["project_id"]) if ref.get("project_id") else None,
                        ref.get("context") or "",
                    ),
                )
            await db.commit()

    async def clear_file_references(self, file_path: Path) -> None:
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                "DELETE FROM index_references WHERE file_path = ?",
                (str(file_path),),
            )
            await db.commit()

    async def remove_file(self, file_path: Path) -> int:
        path = str(file_path)
        async with aiosqlite.connect(self._database_path) as db:
            cursor = await db.execute(
                "SELECT COUNT(*) FROM index_symbols WHERE file_path = ?",
                (path,),
            )
            row = await cursor.fetchone()
            count = int(row[0]) if row else 0
            await db.execute("DELETE FROM index_symbols WHERE file_path = ?", (path,))
            await db.execute("DELETE FROM index_files WHERE file_path = ?", (path,))
            await db.execute("DELETE FROM index_references WHERE file_path = ?", (path,))
            await db.commit()
        return count

    async def get_file_mtime(self, file_path: Path) -> float | None:
        async with aiosqlite.connect(self._database_path) as db:
            cursor = await db.execute(
                "SELECT mtime FROM index_files WHERE file_path = ?",
                (str(file_path),),
            )
            row = await cursor.fetchone()
        return float(row[0]) if row else None

    async def list_indexed_files(
        self,
        workspace_id: UUID | None = None,
        *,
        project_id: UUID | None = None,
    ) -> list[str]:
        async with aiosqlite.connect(self._database_path) as db:
            if project_id is not None:
                cursor = await db.execute(
                    "SELECT file_path FROM index_files WHERE project_id = ?",
                    (str(project_id),),
                )
            elif workspace_id:
                cursor = await db.execute(
                    "SELECT file_path FROM index_files WHERE workspace_id = ?",
                    (str(workspace_id),),
                )
            else:
                cursor = await db.execute("SELECT file_path FROM index_files")
            rows = await cursor.fetchall()
        return [row[0] for row in rows]

    async def search_symbols(
        self,
        query: str,
        *,
        project_id: UUID | None = None,
        kind: SymbolKind | None = None,
        limit: int = 100,
    ) -> list[dict]:
        needle = (query or "").strip().lower()
        clauses = ["1=1"]
        params: list[object] = []
        if project_id:
            clauses.append("project_id = ?")
            params.append(str(project_id))
        if kind:
            clauses.append("kind = ?")
            params.append(kind.value)
        elif not needle:
            # Empty browse: skip tags (they dominate large RF projects).
            clauses.append("kind != ?")
            params.append(SymbolKind.TAG.value)
        if needle:
            clauses.append("(name_lower LIKE ? OR detail LIKE ? OR documentation LIKE ?)")
            like = f"%{needle}%"
            params.extend([like, like, like])
        params.append(limit)
        sql = f"""
            SELECT * FROM index_symbols
            WHERE {' AND '.join(clauses)}
            ORDER BY
                CASE
                    WHEN name_lower = ? THEN 0
                    WHEN name_lower LIKE ? THEN 1
                    ELSE 2
                END,
                name_lower
            LIMIT ?
        """
        # Rebuild with ranking params after WHERE params, before LIMIT.
        where_params = params[:-1]
        rank_exact = needle
        rank_prefix = f"{needle}%"
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                sql,
                [*where_params, rank_exact, rank_prefix, limit],
            )
            rows = await cursor.fetchall()
        results = [self._row_to_dict(row) for row in rows]
        if needle:
            results.sort(key=lambda item: self._fuzzy_score(needle, item["name"]))
        results = self._dedupe_search_results(results, kind=kind)
        # Prefer keywords/tests/variables over tags when kind is unconstrained.
        if kind is None:
            results.sort(key=lambda item: self._kind_rank(item.get("kind")))
            if needle:
                results.sort(
                    key=lambda item: (
                        self._kind_rank(item.get("kind")),
                        *self._fuzzy_score(needle, item["name"]),
                    ),
                )
        return results[:limit]

    @staticmethod
    def _kind_rank(kind: str | None) -> int:
        order = {
            "keyword": 0,
            "test_case": 1,
            "variable": 2,
            "test_suite": 3,
            "resource": 4,
            "library": 5,
            "file": 6,
            "tag": 8,
        }
        return order.get(str(kind or ""), 7)

    @staticmethod
    def _dedupe_search_results(
        results: list[dict],
        *,
        kind: SymbolKind | None,
    ) -> list[dict]:
        """Collapse duplicate tag names into a single hit with usage count."""
        if kind is not None and kind != SymbolKind.TAG:
            return results
        seen_tags: dict[str, dict] = {}
        out: list[dict] = []
        for item in results:
            if str(item.get("kind") or "") != SymbolKind.TAG.value:
                out.append(item)
                continue
            key = str(item.get("name") or "").lower()
            if key in seen_tags:
                prev = seen_tags[key]
                count = int(prev.get("_count") or 1) + 1
                prev["_count"] = count
                prev["detail"] = f"used in {count} places"
                continue
            item = dict(item)
            item["_count"] = 1
            if not item.get("detail"):
                item["detail"] = "tag"
            seen_tags[key] = item
            out.append(item)
        for item in out:
            item.pop("_count", None)
        return out

    async def find_references(self, symbol_id: str) -> list[dict]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            symbol = await self.get_symbol(symbol_id)
            if symbol is None:
                return []
            cursor = await db.execute(
                """
                SELECT * FROM index_references
                WHERE symbol_id = ? OR name_lower = ?
                ORDER BY file_path, line
                """,
                (symbol_id, symbol["name"].lower()),
            )
            rows = await cursor.fetchall()
        return [
            {
                "symbol_id": row["symbol_id"],
                "name": row["name"],
                "file_path": row["file_path"],
                "line": row["line"],
                "project_id": row["project_id"],
                "context": row["context"],
            }
            for row in rows
        ]

    async def get_symbol(self, symbol_id: str) -> dict | None:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM index_symbols WHERE id = ?",
                (symbol_id,),
            )
            row = await cursor.fetchone()
        return self._row_to_dict(row) if row else None

    async def find_definition(
        self,
        name: str,
        *,
        kind: SymbolKind | None = None,
    ) -> dict | None:
        hits = await self.find_definitions(name, kind=kind, limit=1)
        return hits[0] if hits else None

    async def find_definitions(
        self,
        name: str,
        *,
        kind: SymbolKind | None = None,
        limit: int = 20,
    ) -> list[dict]:
        clauses = ["name_lower = ?"]
        params: list[object] = [name.lower()]
        if kind:
            clauses.append("kind = ?")
            params.append(kind.value)
        params.append(limit)
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                f"""
                SELECT * FROM index_symbols
                WHERE {' AND '.join(clauses)}
                ORDER BY
                    CASE kind
                        WHEN 'keyword' THEN 0
                        WHEN 'variable' THEN 1
                        WHEN 'test' THEN 2
                        WHEN 'library' THEN 3
                        WHEN 'resource' THEN 4
                        ELSE 5
                    END,
                    file_path,
                    line
                LIMIT ?
                """,
                params,
            )
            rows = await cursor.fetchall()
        return [self._row_to_dict(row) for row in rows]

    async def symbols_for_file(self, file_path: Path) -> list[dict]:
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                """
                SELECT * FROM index_symbols
                WHERE file_path = ?
                ORDER BY line, name_lower
                """,
                (str(file_path),),
            )
            rows = await cursor.fetchall()
        return [self._row_to_dict(row) for row in rows]

    async def status(self, workspace_id: UUID | None = None) -> dict:
        where = "WHERE workspace_id = ?" if workspace_id else ""
        params: tuple = (str(workspace_id),) if workspace_id else ()
        async with aiosqlite.connect(self._database_path) as db:
            cursor = await db.execute(
                f"SELECT COUNT(*) FROM index_files {where}",
                params,
            )
            files = int((await cursor.fetchone())[0])
            cursor = await db.execute(
                f"SELECT COUNT(*) FROM index_symbols {where}",
                params,
            )
            symbols = int((await cursor.fetchone())[0])
            cursor = await db.execute(
                f"SELECT COUNT(*) FROM index_symbols {where} {'AND' if where else 'WHERE'} kind = 'keyword'",
                params,
            )
            keywords = int((await cursor.fetchone())[0])
            cursor = await db.execute(
                f"SELECT COUNT(*) FROM index_symbols {where} {'AND' if where else 'WHERE'} kind = 'library'",
                params,
            )
            libraries = int((await cursor.fetchone())[0])
            cursor = await db.execute(
                f"SELECT COUNT(*) FROM index_symbols {where} {'AND' if where else 'WHERE'} kind = 'variable'",
                params,
            )
            variables = int((await cursor.fetchone())[0])
            cursor = await db.execute(
                "SELECT value FROM index_meta WHERE key = 'last_indexed_at'",
            )
            last_row = await cursor.fetchone()
        last_indexed = None
        if last_row and last_row[0]:
            last_indexed = datetime.fromisoformat(last_row[0])
        return {
            "files_indexed": files,
            "symbols_indexed": symbols,
            "keywords_indexed": keywords,
            "libraries_indexed": libraries,
            "variables_indexed": variables,
            "last_indexed_at": last_indexed,
        }

    @staticmethod
    def _row_to_dict(row: aiosqlite.Row) -> dict:
        return {
            "id": row["id"],
            "name": row["name"],
            "kind": row["kind"],
            "file_path": row["file_path"],
            "line": row["line"],
            "project_id": row["project_id"],
            "workspace_id": row["workspace_id"],
            "documentation": row["documentation"] or "",
            "detail": row["detail"] or "",
            "last_modified": row["last_modified"],
        }

    @staticmethod
    def _fuzzy_score(query: str, name: str) -> tuple[int, int, str]:
        lower = name.lower()
        if lower == query:
            return (0, 0, lower)
        if lower.startswith(query):
            return (1, len(lower), lower)
        if query in lower:
            return (2, lower.find(query), lower)
        # subsequence score
        qi = 0
        for ch in lower:
            if qi < len(query) and ch == query[qi]:
                qi += 1
        if qi == len(query):
            return (3, len(lower), lower)
        return (9, len(lower), lower)
