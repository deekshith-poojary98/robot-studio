"""Git domain models."""

from __future__ import annotations

from datetime import UTC, datetime
from enum import Enum
from pathlib import Path

from pydantic import BaseModel, Field


class GitFileStatus(str, Enum):
    MODIFIED = "modified"
    ADDED = "added"
    DELETED = "deleted"
    RENAMED = "renamed"
    UNTRACKED = "untracked"
    COPIED = "copied"


class GitFileChange(BaseModel):
    path: str
    status: GitFileStatus
    old_path: str | None = None


class GitRemote(BaseModel):
    name: str
    url: str


class GitIdentity(BaseModel):
    """Effective Git author used for new commits."""

    name: str = ""
    email: str = ""
    source: str = "unset"  # local | global | unset

    @property
    def is_complete(self) -> bool:
        return bool(self.name.strip() and "@" in self.email)


class GitRepositoryInfo(BaseModel):
    is_repository: bool = True
    root: Path | None = None
    branch: str | None = None
    head: str | None = None
    detached: bool = False
    clean: bool = True
    remotes: list[GitRemote] = Field(default_factory=list)
    identity: GitIdentity = Field(default_factory=GitIdentity)


class GitStatus(BaseModel):
    repository: GitRepositoryInfo
    changes: list[GitFileChange] = Field(default_factory=list)


class GitCommit(BaseModel):
    hash: str
    short_hash: str
    author: str
    email: str = ""
    date: datetime
    message: str


class GitCommitDetail(GitCommit):
    files: list[GitFileChange] = Field(default_factory=list)


class GitBranch(BaseModel):
    name: str
    current: bool = False
    remote: bool = False


class GitDiffLine(BaseModel):
    kind: str  # context, added, removed
    left: str = ""
    right: str = ""
    left_line: int | None = None
    right_line: int | None = None


class GitDiff(BaseModel):
    file_path: str | None = None
    old_path: str | None = None
    lines: list[GitDiffLine] = Field(default_factory=list)


class GitRemoteResult(BaseModel):
    success: bool
    message: str = ""
    output: str = ""
