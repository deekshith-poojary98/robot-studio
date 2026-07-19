"""Polling file watcher for Robot/Python sources."""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from pathlib import Path

from robot_studio.domain.interfaces.indexing import FileWatcher
from robot_studio.infrastructure.indexing.filesystem_indexer import INDEXABLE_SUFFIXES

ChangeHandler = Callable[[str, Path], Awaitable[None]]


@dataclass
class PollingFileWatcher(FileWatcher):
    """Lightweight mtime poller — avoids adding a watchdog dependency."""

    interval_seconds: float = 1.5
    on_change: ChangeHandler | None = None
    _roots: set[Path] = field(default_factory=set)
    _snapshot: dict[str, float] = field(default_factory=dict)
    _task: asyncio.Task | None = field(default=None, init=False)
    _running: bool = field(default=False, init=False)

    async def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._snapshot = self._scan()
        self._task = asyncio.create_task(self._loop())

    async def stop(self) -> None:
        self._running = False
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None

    def watch_path(self, path: Path) -> None:
        self._roots.add(Path(path))

    def unwatch_path(self, path: Path) -> None:
        self._roots.discard(Path(path))

    @property
    def is_running(self) -> bool:
        return self._running

    async def _loop(self) -> None:
        while self._running:
            await asyncio.sleep(self.interval_seconds)
            try:
                await self._poll()
            except Exception:
                continue

    async def _poll(self) -> None:
        current = self._scan()
        previous = self._snapshot
        created_or_modified = []
        for path, mtime in current.items():
            old = previous.get(path)
            if old is None:
                created_or_modified.append(("created", Path(path)))
            elif abs(old - mtime) > 1e-6:
                created_or_modified.append(("modified", Path(path)))
        deleted = [Path(path) for path in previous if path not in current]
        self._snapshot = current
        if self.on_change is None:
            return
        for event, path in created_or_modified:
            await self.on_change(event, path)
        for path in deleted:
            await self.on_change("deleted", path)

    def _scan(self) -> dict[str, float]:
        result: dict[str, float] = {}
        for root in list(self._roots):
            if not root.exists():
                continue
            for path in root.rglob("*"):
                if not path.is_file():
                    continue
                if path.suffix.lower() not in INDEXABLE_SUFFIXES:
                    continue
                parts = {part.lower() for part in path.parts}
                if parts & {"__pycache__", ".venv", "venv", "node_modules", ".git"}:
                    continue
                if "Environments" in path.parts:
                    continue
                try:
                    result[str(path)] = path.stat().st_mtime
                except OSError:
                    continue
        return result
