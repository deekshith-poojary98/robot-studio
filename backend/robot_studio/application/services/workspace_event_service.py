"""Live workspace event fan-out — EventBus + FS watcher → WebSocket queues."""

from __future__ import annotations

import asyncio
import logging
from contextlib import suppress
from dataclasses import dataclass, field
from pathlib import Path

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import (
    EnvironmentActivated,
    EnvironmentCloned,
    EnvironmentCreated,
    EnvironmentDeleted,
    EnvironmentImported,
    EventBus,
    FilesystemChanged,
    IndexProgress,
    IndexUpdated,
    AnalysisProgress,
    ProjectOpened,
    RepositoryUpdated,
    Subscription,
    WorkspaceClosed,
    WorkspaceOpened,
)

logger = logging.getLogger(__name__)


@dataclass
class _Subscriber:
    queue: asyncio.Queue[dict]


@dataclass
class WorkspaceEventService:
    """Bridges domain + filesystem events to `/api/v1/workspace/events`."""

    context: WorkspaceContext
    event_bus: EventBus
    watcher: object  # Native/PollingFileWatcher with optional on_fs_change
    root_poll_seconds: float = 2.0
    _subscribers: list[_Subscriber] = field(default_factory=list, init=False)
    _unsubscribes: list[Subscription] = field(default_factory=list, init=False)
    _subscribed: bool = field(default=False, init=False)
    _missing_workspace_sent: bool = field(default=False, init=False)
    _missing_project_sent: bool = field(default=False, init=False)
    _root_poll_task: asyncio.Task | None = field(default=None, init=False)

    def start(self) -> None:
        if self._subscribed:
            return
        self._unsubscribes = [
            self.event_bus.subscribe(FilesystemChanged, self._on_filesystem_changed),
            self.event_bus.subscribe(IndexUpdated, self._on_index_updated),
            self.event_bus.subscribe(IndexProgress, self._on_index_progress),
            self.event_bus.subscribe(AnalysisProgress, self._on_analysis_progress),
            self.event_bus.subscribe(RepositoryUpdated, self._on_repository_updated),
            self.event_bus.subscribe(WorkspaceOpened, self._on_workspace_opened),
            self.event_bus.subscribe(WorkspaceClosed, self._on_workspace_closed),
            self.event_bus.subscribe(ProjectOpened, self._on_project_opened),
            self.event_bus.subscribe(EnvironmentCreated, self._on_environment_changed),
            self.event_bus.subscribe(EnvironmentImported, self._on_environment_changed),
            self.event_bus.subscribe(EnvironmentActivated, self._on_environment_changed),
            self.event_bus.subscribe(EnvironmentCloned, self._on_environment_changed),
            self.event_bus.subscribe(EnvironmentDeleted, self._on_environment_changed),
        ]
        if hasattr(self.watcher, "on_fs_change"):
            self.watcher.on_fs_change = self._on_watcher_fs_change  # type: ignore[attr-defined]
        self._subscribed = True
        self._start_root_poll()

    def _start_root_poll(self) -> None:
        """Poll the roots directly.

        Deleting the watched root itself produces no watcher events (watchdog
        loses the directory it observes, and the poller skips absent roots), so
        fs-event-driven checks alone never notice a removed workspace/project.
        """
        if self._root_poll_task is not None and not self._root_poll_task.done():
            return
        try:
            asyncio.get_running_loop()
        except RuntimeError:
            return
        self._root_poll_task = asyncio.create_task(
            self._poll_roots(),
            name="workspace-root-liveness",
        )

    async def _poll_roots(self) -> None:
        while self._subscribed:
            await asyncio.sleep(self.root_poll_seconds)
            try:
                await self._check_roots_missing()
            except asyncio.CancelledError:
                raise
            except Exception:  # noqa: BLE001 - liveness poll must never die
                logger.debug("Root liveness check failed", exc_info=True)

    async def stop(self) -> None:
        for subscription in self._unsubscribes:
            subscription.unsubscribe()
        self._unsubscribes.clear()
        self._subscribed = False
        if hasattr(self.watcher, "on_fs_change"):
            self.watcher.on_fs_change = None  # type: ignore[attr-defined]
        task = self._root_poll_task
        self._root_poll_task = None
        if task is not None and not task.done():
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task
        self._subscribers.clear()

    async def subscribe(self) -> asyncio.Queue[dict]:
        queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=1000)
        self._subscribers.append(_Subscriber(queue=queue))
        # Covers start() having run without a loop to schedule the poll on.
        self._start_root_poll()
        return queue

    async def unsubscribe(self, queue: asyncio.Queue[dict]) -> None:
        self._subscribers = [
            item for item in self._subscribers if item.queue is not queue
        ]

    async def _on_watcher_fs_change(
        self,
        event: str,
        path: Path,
        *,
        is_dir: bool = False,
        dest_path: Path | None = None,
    ) -> None:
        kind = self._map_watcher_event(event, is_dir=is_dir)
        if kind is None:
            return

        if event == "renamed":
            domain = FilesystemChanged(
                kind=kind,
                path=str(dest_path) if dest_path is not None else str(path),
                old_path=str(path),
                is_directory=is_dir,
            )
        else:
            absolute = str(path)
            try:
                if path.exists():
                    absolute = str(path.resolve())
            except OSError:
                absolute = str(path)
            domain = FilesystemChanged(
                kind=kind,
                path=absolute,
                is_directory=is_dir,
            )

        await self.event_bus.publish(domain)
        await self._check_roots_missing()

    @staticmethod
    def _map_watcher_event(event: str, *, is_dir: bool) -> str | None:
        if event == "created":
            return "DIRECTORY_CREATED" if is_dir else "FILE_CREATED"
        if event == "deleted":
            return "DIRECTORY_DELETED" if is_dir else "FILE_DELETED"
        if event == "modified":
            return None if is_dir else "FILE_MODIFIED"
        if event == "renamed":
            return "DIRECTORY_RENAMED" if is_dir else "FILE_RENAMED"
        return None

    async def _on_filesystem_changed(self, event: FilesystemChanged) -> None:
        payload: dict = {
            "type": event.kind,
            "path": self._display_path(event.path),
            "absolute_path": event.path,
        }
        if event.old_path:
            payload["old_path"] = self._display_path(event.old_path)
            payload["old_absolute_path"] = event.old_path
        if event.is_directory:
            payload["is_directory"] = True
        await self._broadcast(payload)
        if event.kind.startswith(("FILE_", "DIRECTORY_")):
            await self._broadcast({"type": "GIT_CHANGED", "path": payload["path"]})

    async def _on_index_updated(self, event: IndexUpdated) -> None:
        await self._broadcast(
            {
                "type": "INDEX_UPDATED",
                "scope": event.scope,
                "scope_id": event.scope_id,
            }
        )

    async def _on_index_progress(self, event: IndexProgress) -> None:
        await self._broadcast(
            {
                "type": "INDEX_PROGRESS",
                "message": event.message,
                "current": event.current,
                "total": event.total,
                "path": event.path,
                "scope": event.scope,
                "scope_id": event.scope_id,
            }
        )

    async def _on_analysis_progress(self, event: AnalysisProgress) -> None:
        await self._broadcast(
            {
                "type": "ANALYSIS_PROGRESS",
                "message": event.message,
                "current": event.current,
                "total": event.total,
                "scope": event.scope,
                "scope_id": event.scope_id,
            }
        )

    async def _on_repository_updated(self, event: RepositoryUpdated) -> None:
        await self._broadcast({"type": "GIT_CHANGED", "path": event.root})

    async def _on_workspace_opened(self, event: WorkspaceOpened) -> None:
        self._missing_workspace_sent = False
        self._missing_project_sent = False
        await self._broadcast(
            {
                "type": "WORKSPACE_CHANGED",
                "workspace_id": str(event.workspace_id),
                "reason": "opened",
            }
        )

    async def _on_workspace_closed(self, event: WorkspaceClosed) -> None:
        await self._broadcast(
            {
                "type": "WORKSPACE_CHANGED",
                "workspace_id": str(event.workspace_id),
                "reason": "closed",
            }
        )

    async def _on_project_opened(self, event: ProjectOpened) -> None:
        self._missing_project_sent = False
        await self._broadcast(
            {
                "type": "PROJECT_CHANGED",
                "project_id": str(event.project_id),
                "workspace_id": str(event.workspace_id),
                "reason": "opened",
            }
        )

    async def _on_environment_changed(self, event: object) -> None:
        payload: dict = {"type": "ENVIRONMENT_CHANGED"}
        environment_id = getattr(event, "environment_id", None)
        if environment_id is not None:
            payload["environment_id"] = str(environment_id)
        await self._broadcast(payload)

    async def _check_roots_missing(self) -> None:
        workspace_missing = False
        workspace = self.context.workspace
        if workspace is not None:
            present = Path(workspace.path).is_dir()
            workspace_missing = not present
            if not present and not self._missing_workspace_sent:
                self._missing_workspace_sent = True
                await self._broadcast(
                    {
                        "type": "WORKSPACE_CHANGED",
                        "workspace_id": str(workspace.id),
                        "path": str(workspace.path),
                        "reason": "missing",
                    }
                )
            elif present:
                self._missing_workspace_sent = False
        project = self.context.project
        if project is not None:
            present = Path(project.path).is_dir()
            # A missing workspace already covers everything inside it; emitting
            # both would stack two dialogs for standalone projects.
            if not present and not workspace_missing and not self._missing_project_sent:
                self._missing_project_sent = True
                await self._broadcast(
                    {
                        "type": "PROJECT_CHANGED",
                        "project_id": str(project.id),
                        "path": str(project.path),
                        "reason": "missing",
                    }
                )
            elif present:
                self._missing_project_sent = False

    def _display_path(self, absolute: str) -> str:
        workspace = self.context.workspace
        if workspace is None:
            return absolute
        try:
            return str(
                Path(absolute).resolve().relative_to(Path(workspace.path).resolve())
            )
        except (ValueError, OSError):
            return absolute

    async def _broadcast(self, message: dict) -> None:
        stale: list[_Subscriber] = []
        for subscriber in list(self._subscribers):
            try:
                subscriber.queue.put_nowait(message)
            except asyncio.QueueFull:
                try:
                    _ = subscriber.queue.get_nowait()
                    subscriber.queue.put_nowait(message)
                except Exception:
                    stale.append(subscriber)
                    logger.warning("Dropping stalled workspace event subscriber")
        if stale:
            self._subscribers = [
                item for item in self._subscribers if item not in stale
            ]
