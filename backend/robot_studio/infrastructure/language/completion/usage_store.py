"""Persist completion acceptance / usage counts for ranking."""

from __future__ import annotations

from pathlib import Path
from uuid import UUID

import aiosqlite


class SqliteCompletionUsageStore:
    """Project-scoped completion usage for ranking boosts."""

    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    async def ensure_schema(self) -> None:
        self._database_path.parent.mkdir(parents=True, exist_ok=True)
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS completion_usage (
                    project_id TEXT NOT NULL,
                    label TEXT NOT NULL,
                    kind TEXT NOT NULL DEFAULT '',
                    count INTEGER NOT NULL DEFAULT 0,
                    last_used_at TEXT,
                    PRIMARY KEY (project_id, label, kind)
                )
                """,
            )
            await db.commit()

    async def record(
        self,
        *,
        project_id: UUID | str,
        label: str,
        kind: str = "",
    ) -> None:
        cleaned = (label or "").strip()
        if not cleaned:
            return
        pid = str(project_id)
        async with aiosqlite.connect(self._database_path) as db:
            await db.execute(
                """
                INSERT INTO completion_usage (project_id, label, kind, count, last_used_at)
                VALUES (?, ?, ?, 1, datetime('now'))
                ON CONFLICT(project_id, label, kind) DO UPDATE SET
                    count = count + 1,
                    last_used_at = datetime('now')
                """,
                (pid, cleaned, kind or ""),
            )
            await db.commit()

    async def usage_map(
        self,
        project_id: UUID | str,
        *,
        limit: int = 500,
    ) -> dict[str, int]:
        """Map ``kind:label.casefold()`` → count."""
        pid = str(project_id)
        async with aiosqlite.connect(self._database_path) as db:
            db.row_factory = aiosqlite.Row
            cur = await db.execute(
                """
                SELECT label, kind, count FROM completion_usage
                WHERE project_id = ?
                ORDER BY count DESC
                LIMIT ?
                """,
                (pid, limit),
            )
            rows = await cur.fetchall()
        out: dict[str, int] = {}
        for row in rows:
            key = f"{row['kind']}:{str(row['label']).casefold()}"
            out[key] = int(row["count"] or 0)
        return out
