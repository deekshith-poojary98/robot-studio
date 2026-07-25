"""Git provider port."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path

from robot_studio.domain.models.git import (
    GitBranch,
    GitCommit,
    GitCommitDetail,
    GitDiff,
    GitRemoteResult,
    GitRepositoryInfo,
    GitStatus,
)


class GitProvider(ABC):
    @abstractmethod
    async def detect(self, path: Path) -> GitRepositoryInfo | None: ...

    @abstractmethod
    async def init(self, path: Path) -> GitRepositoryInfo: ...

    @abstractmethod
    async def status(self, repo_root: Path) -> GitStatus: ...

    @abstractmethod
    async def history(self, repo_root: Path, *, limit: int = 50) -> list[GitCommit]: ...

    @abstractmethod
    async def commit_detail(
        self,
        repo_root: Path,
        commit_hash: str,
    ) -> GitCommitDetail: ...

    @abstractmethod
    async def branches(self, repo_root: Path) -> list[GitBranch]: ...

    @abstractmethod
    async def checkout(self, repo_root: Path, branch: str) -> GitRepositoryInfo: ...

    @abstractmethod
    async def create_branch(
        self,
        repo_root: Path,
        name: str,
        *,
        start_point: str | None = None,
    ) -> GitBranch: ...

    @abstractmethod
    async def delete_branch(self, repo_root: Path, name: str) -> None: ...

    @abstractmethod
    async def commit(
        self,
        repo_root: Path,
        message: str,
        *,
        files: list[str] | None = None,
    ) -> GitCommit: ...

    @abstractmethod
    async def fetch(self, repo_root: Path) -> GitRemoteResult: ...

    @abstractmethod
    async def pull(self, repo_root: Path) -> GitRemoteResult: ...

    @abstractmethod
    async def push(self, repo_root: Path) -> GitRemoteResult: ...

    @abstractmethod
    async def seed_local_remote(
        self,
        repo_root: Path,
        *,
        relative_path: str = ".test-remotes/origin.git",
        remote_name: str = "origin",
    ) -> str: ...

    @abstractmethod
    async def diff(
        self,
        repo_root: Path,
        *,
        file_path: str | None = None,
        commit: str | None = None,
    ) -> GitDiff: ...
