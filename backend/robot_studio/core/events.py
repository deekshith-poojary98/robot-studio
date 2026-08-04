"""In-process event bus for decoupled module communication."""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from collections import defaultdict
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from uuid import UUID

logger = logging.getLogger(__name__)

EventHandler = Callable[["DomainEvent"], Awaitable[None]]


@dataclass(frozen=True, kw_only=True)
class DomainEvent:
    """Base type for all domain events."""


@dataclass(frozen=True)
class WorkspaceOpened(DomainEvent):
    workspace_id: UUID


@dataclass(frozen=True)
class WorkspaceClosed(DomainEvent):
    workspace_id: UUID


@dataclass(frozen=True)
class ProjectCreated(DomainEvent):
    workspace_id: UUID
    project_id: UUID


@dataclass(frozen=True)
class ProjectImported(DomainEvent):
    workspace_id: UUID
    project_id: UUID


@dataclass(frozen=True)
class ProjectOpened(DomainEvent):
    workspace_id: UUID
    project_id: UUID


@dataclass(frozen=True)
class EnvironmentCreated(DomainEvent):
    workspace_id: UUID
    environment_id: UUID


@dataclass(frozen=True)
class EnvironmentImported(DomainEvent):
    workspace_id: UUID
    environment_id: UUID


@dataclass(frozen=True)
class EnvironmentActivated(DomainEvent):
    workspace_id: UUID
    environment_id: UUID


@dataclass(frozen=True)
class EnvironmentCloned(DomainEvent):
    workspace_id: UUID
    source_environment_id: UUID
    environment_id: UUID


@dataclass(frozen=True)
class EnvironmentDeleted(DomainEvent):
    workspace_id: UUID
    environment_id: UUID


@dataclass(frozen=True)
class PackageInstalled(DomainEvent):
    workspace_id: UUID
    environment_id: UUID
    package_name: str


@dataclass(frozen=True)
class PackageUpdated(DomainEvent):
    workspace_id: UUID
    environment_id: UUID
    package_name: str


@dataclass(frozen=True)
class PackageRemoved(DomainEvent):
    workspace_id: UUID
    environment_id: UUID
    package_name: str


@dataclass(frozen=True)
class RobotFrameworkInstalled(DomainEvent):
    workspace_id: UUID
    environment_id: UUID
    version: str | None = None


@dataclass(frozen=True)
class IndexUpdated(DomainEvent):
    scope: str
    scope_id: str | None = None


@dataclass(frozen=True)
class IndexProgress(DomainEvent):
    """Mid-rebuild progress for status bar / live workspace events."""

    message: str
    current: int = 0
    total: int = 0
    path: str | None = None
    scope: str = "workspace"
    scope_id: str | None = None


@dataclass(frozen=True)
class AnalysisProgress(DomainEvent):
    """Mid-analysis progress (graph rebuild / bind)."""

    message: str
    current: int = 0
    total: int = 0
    scope: str = "workspace"
    scope_id: str | None = None


@dataclass(frozen=True)
class FileIndexed(DomainEvent):
    path: str
    workspace_id: UUID | None = None
    project_id: UUID | None = None
    symbol_count: int = 0


@dataclass(frozen=True)
class FileRemoved(DomainEvent):
    path: str
    workspace_id: UUID | None = None


@dataclass(frozen=True)
class ExecutionStarted(DomainEvent):
    run_id: UUID
    project_id: UUID
    workspace_id: UUID | None = None


@dataclass(frozen=True)
class ExecutionOutput(DomainEvent):
    run_id: UUID
    line: str


@dataclass(frozen=True)
class ExecutionFinished(DomainEvent):
    run_id: UUID
    status: str
    exit_code: int | None = None


@dataclass(frozen=True)
class ExecutionCancelled(DomainEvent):
    run_id: UUID


@dataclass(frozen=True)
class ExecutionFailed(DomainEvent):
    run_id: UUID
    message: str = ""


@dataclass(frozen=True)
class RunIndexed(DomainEvent):
    run_id: UUID
    workspace_id: UUID | None = None


@dataclass(frozen=True)
class RunDeleted(DomainEvent):
    run_id: UUID
    workspace_id: UUID | None = None


@dataclass(frozen=True)
class RepositoryOpened(DomainEvent):
    root: str


@dataclass(frozen=True)
class RepositoryInitialized(DomainEvent):
    root: str


@dataclass(frozen=True)
class BranchChanged(DomainEvent):
    root: str
    branch: str


@dataclass(frozen=True)
class CommitCreated(DomainEvent):
    root: str
    commit_hash: str


@dataclass(frozen=True)
class RepositoryUpdated(DomainEvent):
    root: str


@dataclass(frozen=True)
class FileWritten(DomainEvent):
    path: str


@dataclass(frozen=True)
class FilesystemChanged(DomainEvent):
    """Debounced filesystem change for live workspace fan-out.

    ``kind`` uses the Tier-1 wire vocabulary (FILE_CREATED, DIRECTORY_DELETED,
    FILE_RENAMED, …). ``path`` / ``old_path`` are absolute paths.
    """

    kind: str
    path: str
    old_path: str | None = None
    is_directory: bool = False


@dataclass(frozen=True)
class PluginLoaded(DomainEvent):
    plugin_id: str


@dataclass(frozen=True)
class PluginEnabled(DomainEvent):
    plugin_id: str


@dataclass(frozen=True)
class PluginDisabled(DomainEvent):
    plugin_id: str


@dataclass(frozen=True)
class PluginFailed(DomainEvent):
    plugin_id: str
    message: str


@dataclass(frozen=True)
class PluginReloaded(DomainEvent):
    plugin_id: str


@dataclass(frozen=True)
class SettingsUpdated(DomainEvent):
    """User preferences changed — consumers should refresh from SettingsService."""

    version: int


@dataclass
class Subscription:
    event_type: type[DomainEvent]
    handler: EventHandler
    unsubscribe: Callable[[], None]


class EventBus(ABC):
    @abstractmethod
    async def publish(self, event: DomainEvent) -> None: ...

    @abstractmethod
    def subscribe(
        self,
        event_type: type[DomainEvent],
        handler: EventHandler,
    ) -> Subscription: ...


@dataclass
class InMemoryEventBus(EventBus):
    """Simple async pub/sub bus for a single backend process."""

    _subscribers: dict[type[DomainEvent], list[EventHandler]] = field(
        default_factory=lambda: defaultdict(list),
    )

    async def publish(self, event: DomainEvent) -> None:
        handlers = list(self._subscribers.get(type(event), []))
        for handler in handlers:
            try:
                await handler(event)
            except Exception:
                logger.exception(
                    "Event handler failed for %s",
                    type(event).__name__,
                )

    def subscribe(
        self,
        event_type: type[DomainEvent],
        handler: EventHandler,
    ) -> Subscription:
        self._subscribers[event_type].append(handler)

        def unsubscribe() -> None:
            handlers = self._subscribers.get(event_type, [])
            if handler in handlers:
                handlers.remove(handler)

        return Subscription(
            event_type=event_type,
            handler=handler,
            unsubscribe=unsubscribe,
        )

    def subscriber_count(self, event_type: type[DomainEvent]) -> int:
        return len(self._subscribers.get(event_type, []))
