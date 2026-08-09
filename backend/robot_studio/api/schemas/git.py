from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from robot_studio.domain.models.git import (
    GitBranch,
    GitCommit,
    GitCommitDetail,
    GitDiff,
    GitDiffLine,
    GitFileChange,
    GitRemote,
    GitRemoteResult,
    GitRepositoryInfo,
    GitStatus,
)


class GitRemoteResponse(BaseModel):
    name: str
    url: str


class GitAddRemoteRequest(BaseModel):
    name: str = "origin"
    url: str


class GitRepositoryResponse(BaseModel):
    is_repository: bool
    root: str | None = None
    branch: str | None = None
    head: str | None = None
    detached: bool = False
    clean: bool = True
    remotes: list[GitRemoteResponse] = Field(default_factory=list)


class GitFileChangeResponse(BaseModel):
    path: str
    status: str
    old_path: str | None = None


class GitStatusResponse(BaseModel):
    repository: GitRepositoryResponse
    changes: list[GitFileChangeResponse] = Field(default_factory=list)


class GitCommitResponse(BaseModel):
    hash: str
    short_hash: str
    author: str
    email: str = ""
    date: datetime
    message: str


class GitCommitDetailResponse(GitCommitResponse):
    files: list[GitFileChangeResponse] = Field(default_factory=list)


class GitBranchResponse(BaseModel):
    name: str
    current: bool = False
    remote: bool = False


class GitDiffLineResponse(BaseModel):
    kind: str
    left: str = ""
    right: str = ""
    left_line: int | None = None
    right_line: int | None = None


class GitDiffResponse(BaseModel):
    file_path: str | None = None
    old_path: str | None = None
    lines: list[GitDiffLineResponse] = Field(default_factory=list)


class GitRemoteResultResponse(BaseModel):
    success: bool
    message: str = ""
    output: str = ""


class GitCommitRequest(BaseModel):
    message: str
    files: list[str] | None = None


class GitCheckoutRequest(BaseModel):
    branch: str


class GitCreateBranchRequest(BaseModel):
    name: str
    start_point: str | None = None


class GitDeleteBranchRequest(BaseModel):
    name: str


def to_repository_response(item: GitRepositoryInfo) -> GitRepositoryResponse:
    return GitRepositoryResponse(
        is_repository=item.is_repository,
        root=str(item.root) if item.root else None,
        branch=item.branch,
        head=item.head,
        detached=item.detached,
        clean=item.clean,
        remotes=[to_remote_info_response(remote) for remote in item.remotes],
    )


def to_remote_info_response(item: GitRemote) -> GitRemoteResponse:
    return GitRemoteResponse(name=item.name, url=item.url)


def to_change_response(item: GitFileChange) -> GitFileChangeResponse:
    return GitFileChangeResponse(
        path=item.path,
        status=item.status.value,
        old_path=item.old_path,
    )


def to_status_response(item: GitStatus) -> GitStatusResponse:
    return GitStatusResponse(
        repository=to_repository_response(item.repository),
        changes=[to_change_response(change) for change in item.changes],
    )


def to_commit_response(item: GitCommit) -> GitCommitResponse:
    return GitCommitResponse(
        hash=item.hash,
        short_hash=item.short_hash,
        author=item.author,
        email=item.email,
        date=item.date,
        message=item.message,
    )


def to_commit_detail_response(item: GitCommitDetail) -> GitCommitDetailResponse:
    return GitCommitDetailResponse(
        **to_commit_response(item).model_dump(),
        files=[to_change_response(change) for change in item.files],
    )


def to_branch_response(item: GitBranch) -> GitBranchResponse:
    return GitBranchResponse(
        name=item.name,
        current=item.current,
        remote=item.remote,
    )


def to_diff_response(item: GitDiff) -> GitDiffResponse:
    return GitDiffResponse(
        file_path=item.file_path,
        old_path=item.old_path,
        lines=[
            GitDiffLineResponse(
                kind=line.kind,
                left=line.left,
                right=line.right,
                left_line=line.left_line,
                right_line=line.right_line,
            )
            for line in item.lines
        ],
    )


def to_remote_response(item: GitRemoteResult) -> GitRemoteResultResponse:
    return GitRemoteResultResponse(
        success=item.success,
        message=item.message,
        output=item.output,
    )
