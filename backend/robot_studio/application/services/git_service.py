"""Git use cases for the active workspace/project."""

from __future__ import annotations

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
    WorkspaceOpened,
)
from robot_studio.domain.interfaces.git import GitProvider
from robot_studio.domain.models.git import (
    GitBranch,
    GitCommit,
    GitCommitDetail,
    GitDiff,
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

    def start(self) -> None:
        if self._subscribed:
            return
        self.event_bus.subscribe(WorkspaceOpened, self._on_workspace_opened)
        self.event_bus.subscribe(ProjectOpened, self._on_project_opened)
        self.event_bus.subscribe(FileWritten, self._on_file_written)
        self._subscribed = True

    async def _on_file_written(self, event: FileWritten) -> None:
        _ = event
        repository = await self.refresh()
        if repository is not None and repository.root is not None:
            await self.event_bus.publish(RepositoryUpdated(root=str(repository.root)))

    async def _on_workspace_opened(self, event: WorkspaceOpened) -> None:
        _ = event
        await self.refresh()

    async def _on_project_opened(self, event: ProjectOpened) -> None:
        _ = event
        await self.refresh()

    def _scope_path(self) -> Path:
        project = self.context.project
        workspace = self.context.workspace
        if project is not None:
            return Path(project.path)
        if workspace is not None:
            return Path(workspace.path)
        raise GitValidationError("Open a workspace before using Git")

    async def refresh(self) -> GitRepositoryInfo | None:
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
        repository = await self.provider.init(path)
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
        created = await self.provider.commit(Path(repo.root), message.strip(), files=files)
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
