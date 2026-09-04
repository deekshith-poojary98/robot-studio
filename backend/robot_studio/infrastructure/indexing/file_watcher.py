"""Filesystem watchers for Robot/Python sources and live workspace events."""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from pathlib import Path

from robot_studio.domain.interfaces.indexing import FileWatcher
from robot_studio.infrastructure.indexing.filesystem_indexer import INDEXABLE_SUFFIXES

ChangeHandler = Callable[[str, Path], Awaitable[None]]
FsChangeHandler = Callable[..., Awaitable[None]]

_SKIP_PARTS = {"__pycache__", ".venv", "venv", "node_modules", ".git"}

_STUDIO_META_DIR = ".robotstudio"
_STUDIO_ENVIRONMENTS = "environments"
_STUDIO_REPORTS = "reports"

# Robot rewrites these constantly during a run — watching them freezes the UI.
_RUN_ARTIFACT_NAMES = {"output.xml", "log.html", "report.html", "xunit.xml"}


def _is_skipped(path: Path) -> bool:
    parts = path.parts
    if {part.lower() for part in parts} & _SKIP_PARTS:
        return True
    if _STUDIO_META_DIR in parts:
        index = parts.index(_STUDIO_META_DIR)
        if len(parts) > index + 1 and parts[index + 1] in {
            _STUDIO_ENVIRONMENTS,
            _STUDIO_REPORTS,
        }:
            return True
    # Legacy Studio env root (pre-.robotstudio/environments).
    if "Environments" in parts:
        return True
    # Artifact names outside studio meta (rare custom --outputdir).
    return path.name.lower() in _RUN_ARTIFACT_NAMES


def _is_indexable(path: Path) -> bool:
    if not path.is_file():
        return False
    if path.suffix.lower() not in INDEXABLE_SUFFIXES:
        return False
    return not _is_skipped(path)


@dataclass
class NativeFileWatcher(FileWatcher):
    """Watchdog-backed filesystem watcher with debounced async callbacks.

    ``on_change`` — indexable Robot/Python files only (IndexService).
    ``on_fs_change`` — all non-skipped files/dirs including renames (live UI).
    """

    debounce_seconds: float = 0.35
    on_change: ChangeHandler | None = None
    on_fs_change: FsChangeHandler | None = None
    _roots: set[Path] = field(default_factory=set)
    _loop: asyncio.AbstractEventLoop | None = field(default=None, init=False)
    _observer: object | None = field(default=None, init=False)
    _handler: object | None = field(default=None, init=False)
    # key → (event, path, is_dir, dest_path)
    _pending: dict[str, tuple[str, Path, bool, Path | None]] = field(
        default_factory=dict,
        init=False,
    )
    _debounce_task: asyncio.Task | None = field(default=None, init=False)
    _running: bool = field(default=False, init=False)

    async def start(self) -> None:
        if self._running:
            return
        from watchdog.events import FileSystemEventHandler
        from watchdog.observers import Observer

        self._loop = asyncio.get_running_loop()
        self._running = True

        class _Handler(FileSystemEventHandler):
            def __init__(self, watcher: NativeFileWatcher) -> None:
                self._watcher = watcher

            def on_created(self, event) -> None:
                self._watcher._schedule(
                    "created",
                    Path(event.src_path),
                    is_dir=bool(getattr(event, "is_directory", False)),
                )

            def on_modified(self, event) -> None:
                self._watcher._schedule(
                    "modified",
                    Path(event.src_path),
                    is_dir=bool(getattr(event, "is_directory", False)),
                )

            def on_deleted(self, event) -> None:
                self._watcher._schedule(
                    "deleted",
                    Path(event.src_path),
                    is_dir=bool(getattr(event, "is_directory", False)),
                )

            def on_moved(self, event) -> None:
                src = Path(event.src_path)
                dest = Path(event.dest_path) if getattr(event, "dest_path", None) else None
                is_dir = bool(getattr(event, "is_directory", False))
                if dest is not None:
                    self._watcher._schedule(
                        "renamed",
                        src,
                        is_dir=is_dir,
                        dest_path=dest,
                    )
                else:
                    self._watcher._schedule("deleted", src, is_dir=is_dir)

        observer = Observer()
        handler = _Handler(self)
        self._handler = handler
        roots = [root for root in list(self._roots) if root.exists()]

        def _attach() -> None:
            for root in roots:
                observer.schedule(handler, str(root), recursive=True)
            observer.daemon = True  # type: ignore[attr-defined]
            observer.start()

        # recursive schedule walks the tree synchronously — don't block the loop.
        await asyncio.to_thread(_attach)
        self._observer = observer

    async def stop(self) -> None:
        self._running = False
        self._loop = None
        if self._observer is not None:
            self._observer.stop()  # type: ignore[union-attr]
            self._observer.join(timeout=2)  # type: ignore[union-attr]
            self._observer = None
        self._handler = None
        if self._debounce_task is not None:
            self._debounce_task.cancel()
            try:
                await self._debounce_task
            except asyncio.CancelledError:
                pass
            self._debounce_task = None
        self._pending.clear()

    def watch_path(self, path: Path) -> None:
        root = Path(path)
        if root in self._roots:
            return
        self._roots.add(root)
        if (
            self._running
            and self._observer is not None
            and self._handler is not None
            and root.exists()
            and self._loop is not None
        ):
            # recursive schedule walks the tree synchronously — never on the loop.
            try:
                self._loop.create_task(self._attach_root(root))
            except RuntimeError:
                return

    async def _attach_root(self, root: Path) -> None:
        def _schedule() -> None:
            if (
                self._observer is not None
                and self._handler is not None
                and root.exists()
            ):
                self._observer.schedule(self._handler, str(root), recursive=True)  # type: ignore[union-attr]

        await asyncio.to_thread(_schedule)

    def unwatch_path(self, path: Path) -> None:
        self._roots.discard(Path(path))

    @property
    def is_running(self) -> bool:
        return self._running

    def _schedule(
        self,
        event: str,
        path: Path,
        *,
        is_dir: bool = False,
        dest_path: Path | None = None,
    ) -> None:
        if not self._running or self._loop is None:
            return
        if _is_skipped(path) or (dest_path is not None and _is_skipped(dest_path)):
            return

        # Index channel: indexable files only (deleted unknown suffix still forwarded).
        wants_index = False
        if not is_dir and self.on_change is not None:
            if event == "deleted":
                wants_index = True
            elif event == "renamed":
                wants_index = _is_indexable(path) or (
                    dest_path is not None and _is_indexable(dest_path)
                )
            elif _is_indexable(path):
                wants_index = True

        wants_fs = self.on_fs_change is not None
        if not wants_index and not wants_fs:
            return
        # Skip directory "modified" noise for both channels when only fs cares about
        # create/delete/rename of dirs.
        if is_dir and event == "modified":
            return

        key = f"{event}:{path}:{dest_path or ''}"
        self._pending[key] = (event, path, is_dir, dest_path)
        loop = self._loop
        try:
            loop.call_soon_threadsafe(self._arm_debounce)
        except RuntimeError:
            return

    def _arm_debounce(self) -> None:
        if not self._running or self._loop is None:
            return
        try:
            asyncio.get_running_loop()
        except RuntimeError:
            return
        if self._debounce_task is not None and not self._debounce_task.done():
            self._debounce_task.cancel()
        self._debounce_task = asyncio.create_task(self._flush_pending())

    async def _flush_pending(self) -> None:
        await asyncio.sleep(self.debounce_seconds)
        pending = list(self._pending.values())
        self._pending.clear()
        for event, path, is_dir, dest_path in pending:
            if self.on_fs_change is not None:
                await self.on_fs_change(
                    event,
                    path,
                    is_dir=is_dir,
                    dest_path=dest_path,
                )
            if self.on_change is None or is_dir:
                continue
            if event == "renamed" and dest_path is not None:
                await self.on_change("deleted", path)
                if dest_path.exists() and _is_indexable(dest_path) or _is_indexable(dest_path) or dest_path.suffix.lower() in INDEXABLE_SUFFIXES:
                    await self.on_change("created", dest_path)
                continue
            if event == "deleted" or _is_indexable(path):
                await self.on_change(event, path)


@dataclass
class PollingFileWatcher(FileWatcher):
    """Lightweight mtime poller — used in tests (avoids watchdog teardown issues)."""

    interval_seconds: float = 1.5
    on_change: ChangeHandler | None = None
    on_fs_change: FsChangeHandler | None = None
    _roots: set[Path] = field(default_factory=set)
    _snapshot: dict[str, float] = field(default_factory=dict)
    _dir_snapshot: set[str] = field(default_factory=set)
    _task: asyncio.Task | None = field(default=None, init=False)
    _running: bool = field(default=False, init=False)

    async def start(self) -> None:
        if self._running:
            return
        self._running = True
        files, dirs = self._scan()
        self._snapshot = files
        self._dir_snapshot = dirs
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
            except Exception:  # noqa: BLE001, S112
                continue

    async def _poll(self) -> None:
        files, dirs = self._scan()
        previous_files = self._snapshot
        previous_dirs = self._dir_snapshot

        fs_events: list[tuple[str, Path, bool, Path | None]] = []
        index_events: list[tuple[str, Path]] = []

        for path, mtime in files.items():
            old = previous_files.get(path)
            p = Path(path)
            if old is None:
                fs_events.append(("created", p, False, None))
                if _is_indexable(p):
                    index_events.append(("created", p))
            elif abs(old - mtime) > 1e-6:
                fs_events.append(("modified", p, False, None))
                if _is_indexable(p):
                    index_events.append(("modified", p))

        for path in previous_files:
            if path not in files:
                p = Path(path)
                fs_events.append(("deleted", p, False, None))
                index_events.append(("deleted", p))

        for path in dirs:
            if path not in previous_dirs:
                fs_events.append(("created", Path(path), True, None))
        for path in previous_dirs:
            if path not in dirs:
                fs_events.append(("deleted", Path(path), True, None))

        self._snapshot = files
        self._dir_snapshot = dirs

        if self.on_fs_change is not None:
            for event, path, is_dir, dest in fs_events:
                await self.on_fs_change(event, path, is_dir=is_dir, dest_path=dest)
        if self.on_change is not None:
            for event, path in index_events:
                await self.on_change(event, path)

    def _scan(self) -> tuple[dict[str, float], set[str]]:
        files: dict[str, float] = {}
        dirs: set[str] = set()
        scan_all = self.on_fs_change is not None
        for root in list(self._roots):
            if not root.exists():
                continue
            for path in root.rglob("*"):
                if _is_skipped(path):
                    continue
                try:
                    if path.is_dir():
                        if scan_all:
                            dirs.add(str(path))
                        continue
                    if not path.is_file():
                        continue
                    if scan_all or path.suffix.lower() in INDEXABLE_SUFFIXES:
                        files[str(path)] = path.stat().st_mtime
                except OSError:
                    continue
        return files, dirs
