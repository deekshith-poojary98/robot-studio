"""Git use cases for the active workspace/project."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from pathlib import Path

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import (
    BranchChanged,
    CommitCreated,
    EventBus,
    FileWritten,
    ProjectOpened,
    RepositoryInitialized,
    RepositoryOpened,
    RepositoryUpdated,
    Subscription,
    WorkspaceOpened,
)
from robot_studio.domain.interfaces.git import GitProvider
from robot_studio.domain.models.git import (
    GitBranch,
    GitCommit,
    GitCommitDetail,
    GitDiff,
    GitIdentity,
    GitRemote,
    GitRemoteResult,
    GitRepositoryInfo,
    GitStatus,
)


class GitValidationError(Exception):
    """Raised when a git operation cannot proceed."""


@dataclass
class GitService:
    context: WorkspaceContext
    event_bus: EventBus
    provider: GitProvider
    _repository: GitRepositoryInfo | None = field(default=None, init=False)
    _subscribed: bool = field(default=False, init=False)
    _background_tasks: set[asyncio.Task] = field(default_factory=set, init=False)
    _unsubscribes: list[Subscription] = field(default_factory=list, init=False)
    _stopped: bool = field(default=False, init=False)
    _refresh_lock: asyncio.Lock = field(default_factory=asyncio.Lock, init=False)

    def start(self) -> None:
        if self._subscribed:
            return
        self._stopped = False
        self._unsubscribes = [
            self.event_bus.subscribe(WorkspaceOpened, self._on_workspace_opened),
            self.event_bus.subscribe(ProjectOpened, self._on_project_opened),
            self.event_bus.subscribe(FileWritten, self._on_file_written),
        ]
        self._subscribed = True

    async def stop(self) -> None:
        self._stopped = True
        for subscription in self._unsubscribes:
            subscription.unsubscribe()
        self._unsubscribes.clear()
        self._subscribed = False
        tasks = list(self._background_tasks)
        self._background_tasks.clear()
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    def _spawn(self, coro: object, *, name: str) -> None:
        if self._stopped:
            return
        task = asyncio.create_task(coro, name=name)  # type: ignore[arg-type]
        self._background_tasks.add(task)
        task.add_done_callback(self._background_tasks.discard)

    async def _on_file_written(self, event: FileWritten) -> None:
        _ = event
        # Never block writers (editor Save) on git status — large repos / dirty
        # trees during long runs made Save appear to hang the whole UI.
        self._spawn(self._refresh_and_publish(), name="git-refresh-on-write")

    async def _refresh_and_publish(self) -> None:
        repository = await self.refresh()
        if repository is not None and repository.root is not None:
            await self.event_bus.publish(RepositoryUpdated(root=str(repository.root)))

    async def _on_workspace_opened(self, event: WorkspaceOpened) -> None:
        _ = event
        # Detect repo without blocking callers for long git ops.
        self._spawn(self.refresh(), name="git-refresh-on-open")

    async def _on_project_opened(self, event: ProjectOpened) -> None:
        _ = event
        self._spawn(self.refresh(), name="git-refresh-on-project")

    def _scope_path(self) -> Path:
        project = self.context.project
        workspace = self.context.workspace
        if project is not None:
            return Path(project.path)
        if workspace is not None:
            return Path(workspace.path)
        raise GitValidationError("Open a workspace before using Git")

    async def refresh(self) -> GitRepositoryInfo | None:
        async with self._refresh_lock:
            try:
                path = self._scope_path()
            except GitValidationError:
                self._repository = None
                return None
            repository = await self.provider.detect(path)
            self._repository = repository
            if repository is not None and repository.is_repository:
                await self.event_bus.publish(RepositoryOpened(root=str(repository.root)))
            return repository

    async def get_repository(self) -> GitRepositoryInfo | None:
        if self._repository is None:
            return await self.refresh()
        return self._repository

    async def status(self) -> GitStatus:
        repo = await self._require_repository()
        status = await self.provider.status(Path(repo.root))
        self._repository = status.repository
        return status

    async def init(self) -> GitRepositoryInfo:
        path = self._scope_path()
        try:
            repository = await self.provider.init(path)
        except Exception as exc:
            from robot_studio.infrastructure.git.cli_provider import GitCommandError

            if isinstance(exc, GitCommandError):
                raise GitValidationError(str(exc)) from exc
            raise
        self._repository = repository
        await self.event_bus.publish(RepositoryInitialized(root=str(repository.root)))
        await self.event_bus.publish(RepositoryUpdated(root=str(repository.root)))
        return repository

    async def history(self, *, limit: int = 50) -> list[GitCommit]:
        repo = await self._require_repository()
        return await self.provider.history(Path(repo.root), limit=limit)

    async def commit_detail(self, commit_hash: str) -> GitCommitDetail:
        repo = await self._require_repository()
        return await self.provider.commit_detail(Path(repo.root), commit_hash)

    async def branches(self) -> list[GitBranch]:
        repo = await self._require_repository()
        return await self.provider.branches(Path(repo.root))

    async def checkout(self, branch: str) -> GitRepositoryInfo:
        repo = await self._require_repository()
        updated = await self.provider.checkout(Path(repo.root), branch)
        self._repository = updated
        await self.event_bus.publish(
            BranchChanged(root=str(updated.root), branch=updated.branch or branch),
        )
        await self.event_bus.publish(RepositoryUpdated(root=str(updated.root)))
        return updated

    async def create_branch(self, name: str, *, start_point: str | None = None) -> GitBranch:
        repo = await self._require_repository()
        branch = await self.provider.create_branch(
            Path(repo.root),
            name,
            start_point=start_point,
        )
        await self.event_bus.publish(RepositoryUpdated(root=str(repo.root)))
        return branch

    async def delete_branch(self, name: str) -> None:
        repo = await self._require_repository()
        await self.provider.delete_branch(Path(repo.root), name)
        await self.event_bus.publish(RepositoryUpdated(root=str(repo.root)))

    async def commit(self, message: str, *, files: list[str] | None = None) -> GitCommit:
        if not message.strip():
            raise GitValidationError("Commit message is required")
        repo = await self._require_repository()
        identity = await self.provider.get_identity(Path(repo.root))
        if not identity.is_complete:
            raise GitValidationError(
                "Git identity is not configured. Set your name and email before committing.",
            )
        try:
            created = await self.provider.commit(Path(repo.root), message.strip(), files=files)
        except Exception as exc:
            from robot_studio.infrastructure.git.cli_provider import GitCommandError

            if isinstance(exc, GitCommandError):
                raise GitValidationError(str(exc)) from exc
            raise
        refreshed = await self.provider.detect(Path(repo.root))
        if refreshed is not None:
            self._repository = refreshed
        await self.event_bus.publish(
            CommitCreated(root=str(repo.root), commit_hash=created.hash),
        )
        await self.event_bus.publish(RepositoryUpdated(root=str(repo.root)))
        return created

    async def fetch(self) -> GitRemoteResult:
        repo = await self._require_repository()
        result = await self.provider.fetch(Path(repo.root))
        if result.success:
            await self.event_bus.publish(RepositoryUpdated(root=str(repo.root)))
        return result

    async def pull(self) -> GitRemoteResult:
        repo = await self._require_repository()
        result = await self.provider.pull(Path(repo.root))
        if result.success:
            refreshed = await self.provider.detect(Path(repo.root))
            if refreshed is not None:
                self._repository = refreshed
            await self.event_bus.publish(RepositoryUpdated(root=str(repo.root)))
        return result

    async def push(self) -> GitRemoteResult:
        repo = await self._require_repository()
        result = await self.provider.push(Path(repo.root))
        return result

    async def list_remotes(self) -> list[GitRemote]:
        repo = await self._require_repository()
        return await self.provider.list_remotes(Path(repo.root))

    async def add_remote(self, *, name: str, url: str) -> list[GitRemote]:
        repo = await self._require_repository()
        try:
            remotes = await self.provider.add_remote(
                Path(repo.root),
                name=name,
                url=url,
            )
        except Exception as exc:
            from robot_studio.infrastructure.git.cli_provider import GitCommandError

            if isinstance(exc, GitCommandError):
                raise GitValidationError(str(exc)) from exc
            raise
        refreshed = await self.provider.detect(Path(repo.root))
        if refreshed is not None:
            self._repository = refreshed
        await self.event_bus.publish(RepositoryUpdated(root=str(repo.root)))
        return remotes

    async def get_identity(self) -> GitIdentity:
        repo = await self._require_repository()
        return await self.provider.get_identity(Path(repo.root))

    async def set_identity(self, *, name: str, email: str, scope: str = "local") -> GitIdentity:
        cleaned_name = name.strip()
        cleaned_email = email.strip()
        if not cleaned_name:
            raise GitValidationError("Name is required")
        if "@" not in cleaned_email:
            raise GitValidationError("A valid email is required")
        if scope not in {"local", "global"}:
            raise GitValidationError("Scope must be local or global")
        repo = await self._require_repository()
        try:
            identity = await self.provider.set_identity(
                Path(repo.root),
                name=cleaned_name,
                email=cleaned_email,
                scope=scope,
            )
        except Exception as exc:
            from robot_studio.infrastructure.git.cli_provider import GitCommandError

            if isinstance(exc, GitCommandError):
                raise GitValidationError(str(exc)) from exc
            raise
        refreshed = await self.provider.detect(Path(repo.root))
        if refreshed is not None:
            self._repository = refreshed
        await self.event_bus.publish(RepositoryUpdated(root=str(repo.root)))
        return identity

    async def seed_local_remote(
        self,
        *,
        relative_path: str = ".test-remotes/origin.git",
        remote_name: str = "origin",
    ) -> str:
        repo = await self._require_repository()
        remote_path = await self.provider.seed_local_remote(
            Path(repo.root),
            relative_path=relative_path,
            remote_name=remote_name,
        )
        await self.event_bus.publish(RepositoryUpdated(root=str(repo.root)))
        return remote_path

    async def diff(
        self,
        *,
        file_path: str | None = None,
        commit: str | None = None,
    ) -> GitDiff:
        repo = await self._require_repository()
        return await self.provider.diff(Path(repo.root), file_path=file_path, commit=commit)

    async def _require_repository(self) -> GitRepositoryInfo:
        repository = await self.get_repository()
        if repository is None or not repository.is_repository or repository.root is None:
            raise GitValidationError("Not a Git repository")
        return repository
