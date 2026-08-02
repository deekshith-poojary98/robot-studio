"""Indexing orchestration — discovers sources, updates IndexStore, emits events."""

from __future__ import annotations

import asyncio
from contextlib import suppress
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import (
    EventBus,
    FileIndexed,
    FileRemoved,
    IndexUpdated,
    ProjectCreated,
    ProjectImported,
    ProjectOpened,
    Subscription,
    WorkspaceOpened,
)
from robot_studio.domain.interfaces.indexing import FileWatcher, IndexScope, SymbolKind
from robot_studio.domain.models import IndexStatus, Project
from robot_studio.infrastructure.indexing.filesystem_indexer import FilesystemIndexer
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.builtin_keywords import BUILTIN_KEYWORDS
from robot_studio.infrastructure.repositories.project_repository import (
    SqliteProjectRepository,
)


class IndexValidationError(Exception):
    """Raised when indexing cannot proceed."""


@dataclass
class IndexService:
    context: WorkspaceContext
    event_bus: EventBus
    store: SqliteIndexStore
    indexer: FilesystemIndexer
    watcher: FileWatcher
    project_repository: SqliteProjectRepository
    _subscribed: bool = field(default=False, init=False)
    _state: str = field(default="idle", init=False)
    _message: str = field(default="", init=False)
    _errors: list[str] = field(default_factory=list, init=False)
    _last_indexed_at: datetime | None = field(default=None, init=False)
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    _rebuild_task: asyncio.Task | None = field(default=None, init=False)
    _unsubscribes: list[Subscription] = field(default_factory=list, init=False)
    _stopped: bool = field(default=False, init=False)

    def start(self) -> None:
        if self._subscribed:
            return
        self._stopped = False
        self._unsubscribes = [
            self.event_bus.subscribe(WorkspaceOpened, self._on_workspace_opened),
            self.event_bus.subscribe(ProjectOpened, self._on_project_changed),
            self.event_bus.subscribe(ProjectCreated, self._on_project_changed),
            self.event_bus.subscribe(ProjectImported, self._on_project_changed),
        ]
        self.watcher.on_change = self._on_file_change
        self._subscribed = True

    async def stop(self) -> None:
        """Release the watcher thread and any in-flight rebuild.

        Stop the watcher before awaiting cancelled rebuild work — otherwise
        filesystem events keep arming debounce tasks while we drain the
        rebuild, and pytest-asyncio's loop teardown livelocks.
        """
        self._stopped = True
        for subscription in self._unsubscribes:
            subscription.unsubscribe()
        self._unsubscribes.clear()
        self._subscribed = False
        self.watcher.on_change = None
        if self.watcher.is_running:
            await self.watcher.stop()
        async with self._lock:
            task = self._rebuild_task
            self._rebuild_task = None
        if task is not None and not task.done():
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task

    async def _on_workspace_opened(self, event: WorkspaceOpened) -> None:
        _ = event
        # Never block open-path / workspace open on indexing (VS Code model).
        await self.schedule_rebuild(full=False)

    async def _on_project_changed(self, event: ProjectOpened | ProjectCreated | ProjectImported) -> None:
        if self.context.workspace is None:
            return
        await self.schedule_reindex_project(event.project_id)

    async def _on_file_change(self, event: str, path: Path) -> None:
        workspace = self.context.workspace
        if workspace is None:
            return
        project_id = await self._resolve_project_id(path)
        if event == "deleted":
            removed = await self.store.remove_file(path)
            if removed:
                await self.event_bus.publish(
                    FileRemoved(path=str(path), workspace_id=workspace.id),
                )
                await self.event_bus.publish(
                    IndexUpdated(scope=IndexScope.FILE.value, scope_id=str(path)),
                )
            return

        count, changed = await self.indexer.index_file(
            path,
            workspace_id=workspace.id,
            project_id=project_id,
        )
        if not changed:
            return
        self._last_indexed_at = datetime.now(UTC)
        await self.event_bus.publish(
            FileIndexed(
                path=str(path),
                workspace_id=workspace.id,
                project_id=project_id,
                symbol_count=count,
            ),
        )
        await self.event_bus.publish(
            IndexUpdated(scope=IndexScope.FILE.value, scope_id=str(path)),
        )

    def _require_workspace(self):
        workspace = self.context.workspace
        if workspace is None:
            raise IndexValidationError("Open a workspace before indexing")
        return workspace

    async def schedule_rebuild(self, *, full: bool = False) -> IndexStatus:
        """Start indexing in the background and return immediately."""
        if self._stopped:
            return await self.get_status()
        workspace = self._require_workspace()
        self._state = "indexing"
        self._message = "Indexing workspace…" if not full else "Rebuilding index…"
        self._errors = []
        async with self._lock:
            if self._rebuild_task and not self._rebuild_task.done():
                return await self.get_status()
            self._rebuild_task = asyncio.create_task(
                self._rebuild_workspace(
                    workspace.id,
                    workspace.path,
                    full=full,
                ),
                name="index-rebuild",
            )
        return await self.get_status()

    async def schedule_reindex_project(self, project_id: UUID) -> IndexStatus:
        """Reindex one project in the background without blocking the caller."""
        if self._stopped:
            return await self.get_status()
        workspace = self._require_workspace()
        project = await self.project_repository.get(project_id)
        if project is None or project.workspace_id != workspace.id:
            return await self.get_status()

        self._state = "indexing"
        self._message = f"Indexing project '{project.name}'…"
        async with self._lock:
            if self._rebuild_task and not self._rebuild_task.done():
                return await self.get_status()
            self._rebuild_task = asyncio.create_task(
                self._reindex_project_root(workspace.id, project),
                name=f"index-project-{project_id}",
            )
        return await self.get_status()

    async def rebuild(self) -> IndexStatus:
        """Explicit rebuild (API / UI) — waits until indexing finishes."""
        workspace = self._require_workspace()
        self._state = "indexing"
        self._message = "Rebuilding index…"
        self._errors = []
        async with self._lock:
            prior = self._rebuild_task
            if prior is not None and not prior.done():
                prior.cancel()
                try:
                    await prior
                except asyncio.CancelledError:
                    pass
            self._rebuild_task = asyncio.create_task(
                self._rebuild_workspace(
                    workspace.id,
                    workspace.path,
                    full=True,
                ),
                name="index-rebuild-full",
            )
            task = self._rebuild_task
        await task
        return await self.get_status()

    async def reindex_project(self, project_id: UUID) -> IndexStatus:
        await self.schedule_reindex_project(project_id)
        task = self._rebuild_task
        if task is not None and not task.done():
            await task
        return await self.get_status()

    async def _rebuild_workspace(
        self,
        workspace_id: UUID,
        workspace_path: Path,
        *,
        full: bool = False,
    ) -> IndexStatus:
        self._state = "indexing"
        self._message = "Indexing workspace…"
        self._errors = []
        try:
            projects = await self.project_repository.list_by_workspace(workspace_id)
            roots: list[tuple[Path, UUID | None]] = []
            for project in projects:
                roots.append((Path(project.path), project.id))
            shared = workspace_path / "Shared"
            if shared.exists():
                roots.append((shared, None))

            for root, project_id in roots:
                self.watcher.watch_path(root)

            # Watch immediately so edits during background index are not missed.
            # Watcher failures must never abort indexing (sandbox / FSEvents issues).
            try:
                if not self.watcher.is_running:
                    await self.watcher.start()
            except Exception as exc:  # noqa: BLE001
                self._errors.append(f"file watcher: {exc}")

            if full:
                await self.store.invalidate(IndexScope.WORKSPACE, str(workspace_id))
            indexed_paths: set[str] = set()

            for root, project_id in roots:
                indexed_paths.update(
                    await self._index_root(
                        workspace_id=workspace_id,
                        root=root,
                        project_id=project_id,
                        force=full,
                        analysis_rebind=False,
                    ),
                )

            for existing in await self.store.list_indexed_files(workspace_id):
                if existing not in indexed_paths and not Path(existing).exists():
                    await self.store.remove_file(Path(existing))
                    await self.event_bus.publish(
                        FileRemoved(path=existing, workspace_id=workspace_id),
                    )

            await self.indexer.finalize_analysis()

            self._last_indexed_at = datetime.now(UTC)
            self._state = "ready"
            self._message = "Index up to date"
            await self.event_bus.publish(
                IndexUpdated(scope=IndexScope.WORKSPACE.value, scope_id=str(workspace_id)),
            )
        except Exception as exc:  # noqa: BLE001
            self._state = "error"
            self._message = str(exc)
            self._errors.append(str(exc))
        return await self.get_status()

    async def _reindex_project_root(self, workspace_id: UUID, project: Project) -> IndexStatus:
        self._state = "indexing"
        self._message = f"Indexing project '{project.name}'…"
        self._errors = []
        try:
            await self.store.invalidate(IndexScope.PROJECT, str(project.id))
            indexed_paths = await self._index_root(
                workspace_id=workspace_id,
                root=Path(project.path),
                project_id=project.id,
                force=True,
                analysis_rebind=False,
            )
            for existing in await self.store.list_indexed_files(
                workspace_id,
                project_id=project.id,
            ):
                if existing not in indexed_paths and not Path(existing).exists():
                    await self.store.remove_file(Path(existing))
                    await self.event_bus.publish(
                        FileRemoved(path=existing, workspace_id=workspace_id),
                    )

            await self.indexer.finalize_analysis()

            self._last_indexed_at = datetime.now(UTC)
            self._state = "ready"
            self._message = "Index up to date"
            await self.event_bus.publish(
                IndexUpdated(scope=IndexScope.PROJECT.value, scope_id=str(project.id)),
            )
            if not self.watcher.is_running:
                try:
                    await self.watcher.start()
                except Exception as exc:  # noqa: BLE001
                    self._errors.append(f"file watcher: {exc}")
        except Exception as exc:  # noqa: BLE001
            self._state = "error"
            self._message = str(exc)
            self._errors.append(str(exc))
        return await self.get_status()

    async def _index_root(
        self,
        *,
        workspace_id: UUID,
        root: Path,
        project_id: UUID | None,
        force: bool = False,
        analysis_rebind: bool = True,
    ) -> set[str]:
        indexed_paths: set[str] = set()
        self.watcher.watch_path(root)
        # Discovery is sync and can touch huge trees — keep the event loop free.
        paths = await asyncio.to_thread(self.indexer.discover_files, root)
        total = len(paths)
        for index, path in enumerate(paths):
            try:
                await self.indexer.index_file(
                    path,
                    workspace_id=workspace_id,
                    project_id=project_id,
                    force=force,
                    analysis_rebind=analysis_rebind,
                )
                indexed_paths.add(str(path))
                # Intentionally no per-file FileIndexed during bulk rebuild.
            except Exception as exc:  # noqa: BLE001
                self._errors.append(f"{path}: {exc}")
            if index % 10 == 0:
                self._message = f"Indexing… {index + 1}/{total}"
                await asyncio.sleep(0)
        return indexed_paths

    async def get_status(self) -> IndexStatus:
        workspace = self.context.workspace
        stats = await self.store.status(workspace.id if workspace else None)
        keywords = int(stats.get("keywords_indexed") or 0)
        # BuiltIn keywords are always searchable even when not on disk.
        if workspace is not None:
            keywords += len(BUILTIN_KEYWORDS)
        return IndexStatus(
            state=self._state if workspace else "idle",
            files_indexed=int(stats.get("files_indexed") or 0),
            keywords_indexed=keywords,
            libraries_indexed=int(stats.get("libraries_indexed") or 0),
            variables_indexed=int(stats.get("variables_indexed") or 0),
            symbols_indexed=int(stats.get("symbols_indexed") or 0),
            last_indexed_at=self._last_indexed_at or stats.get("last_indexed_at"),
            message=self._message if workspace else "No workspace open",
            errors=list(self._errors),
        )

    async def search(
        self,
        query: str,
        *,
        kind: SymbolKind | None = None,
        limit: int = 100,
    ) -> list[dict]:
        self._require_workspace()
        results = await self.store.search_symbols(query, kind=kind, limit=limit)
        if kind in {None, SymbolKind.KEYWORD}:
            results = self._merge_builtin_keywords(results, query=query, limit=limit)
        return results

    def _merge_builtin_keywords(
        self,
        results: list[dict],
        *,
        query: str,
        limit: int,
    ) -> list[dict]:
        needle = (query or "").strip().lower()
        seen = {str(item.get("name", "")).lower() for item in results}
        extras: list[dict] = []
        for name in BUILTIN_KEYWORDS:
            if needle and needle not in name.lower():
                continue
            if name.lower() in seen:
                continue
            extras.append(
                {
                    "id": f"builtin:{name.lower().replace(' ', '-')}",
                    "name": name,
                    "kind": SymbolKind.KEYWORD.value,
                    "file_path": "BuiltIn",
                    "line": 1,
                    "project_id": None,
                    "workspace_id": None,
                    "documentation": "Robot Framework BuiltIn keyword",
                    "detail": "BuiltIn",
                    "last_modified": None,
                }
            )
            seen.add(name.lower())
        # Project / index hits first so empty keyword searches aren't all BuiltIns.
        merged = [*results, *extras]
        if needle:
            merged.sort(
                key=lambda item: (
                    0 if str(item.get("name", "")).lower() == needle else 1,
                    0 if str(item.get("name", "")).lower().startswith(needle) else 1,
                    str(item.get("name", "")).lower(),
                )
            )
        return merged[:limit]

    async def _resolve_project_id(self, path: Path) -> UUID | None:
        workspace = self.context.workspace
        if workspace is None:
            return None
        projects = await self.project_repository.list_by_workspace(workspace.id)
        path_resolved = path.resolve()
        for project in projects:
            root = Path(project.path).resolve()
            try:
                path_resolved.relative_to(root)
                return project.id
            except ValueError:
                continue
        return None
