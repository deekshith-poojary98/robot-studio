"""Unit tests for Git integration."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from robot_studio.application.services.git_service import GitService, GitValidationError
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import (
    BranchChanged,
    CommitCreated,
    InMemoryEventBus,
    RepositoryInitialized,
    RepositoryUpdated,
    WorkspaceOpened,
)
from robot_studio.domain.models import Workspace, WorkspaceSettings
from robot_studio.domain.models.git import GitFileStatus
from robot_studio.infrastructure.git.cli_provider import CliGitProvider


def _run_git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=str(cwd), check=True, capture_output=True)


@pytest.fixture
async def git_stack(tmp_path: Path):
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    workspace_path = tmp_path / "WS"
    workspace_path.mkdir()
    workspace = Workspace(
        id=__import__("uuid").uuid4(),
        name="WS",
        path=workspace_path,
        created_at=__import__("datetime").datetime.now(__import__("datetime").UTC),
        settings=WorkspaceSettings(),
    )
    await context.open(workspace)
    provider = CliGitProvider()
    service = GitService(context=context, event_bus=bus, provider=provider)
    service.start()
    return service, provider, workspace_path, bus


@pytest.mark.asyncio
async def test_detect_no_repository(git_stack) -> None:
    service, _provider, _path, _bus = git_stack
    assert await service.get_repository() is None


@pytest.mark.asyncio
async def test_init_status_commit_checkout_branch(git_stack) -> None:
    service, _provider, workspace_path, bus = git_stack
    events: list[object] = []

    async def capture(event) -> None:
        events.append(event)

    bus.subscribe(RepositoryInitialized, capture)
    bus.subscribe(CommitCreated, capture)
    bus.subscribe(BranchChanged, capture)
    bus.subscribe(RepositoryUpdated, capture)

    repository = await service.init()
    assert repository.is_repository is True
    assert repository.root == workspace_path.resolve()
    _run_git(workspace_path, "config", "user.email", "dev@example.com")
    _run_git(workspace_path, "config", "user.name", "Dev")

    sample = workspace_path / "sample.robot"
    sample.write_text("*** Test Cases ***\nA\n    Log    x\n", encoding="utf-8")

    status = await service.status()
    assert status.repository.is_repository is True
    assert any(
        change.path.endswith("sample.robot")
        and change.status == GitFileStatus.UNTRACKED
        for change in status.changes
    )

    commit = await service.commit("Initial commit")
    assert commit.message == "Initial commit"

    sample.write_text("*** Test Cases ***\nA\n    Log    updated\n", encoding="utf-8")
    dirty = await service.status()
    assert any(change.path.endswith("sample.robot") for change in dirty.changes)

    branch = await service.create_branch("feature/login")
    assert branch.name == "feature/login"

    updated = await service.checkout("feature/login")
    assert updated.branch == "feature/login"

    history = await service.history(limit=5)
    assert len(history) >= 1
    detail = await service.commit_detail(history[0].hash)
    assert detail.files

    diff = await service.diff(file_path=str(sample))
    assert diff.file_path is not None

    all_branches = await service.branches()
    default_branch = next(b.name for b in all_branches if b.name != "feature/login")
    await service.checkout(default_branch)
    await service.delete_branch("feature/login")
    assert any(isinstance(item, RepositoryInitialized) for item in events)
    assert any(isinstance(item, CommitCreated) for item in events)
    assert any(isinstance(item, BranchChanged) for item in events)


@pytest.mark.asyncio
async def test_detect_existing_repository(git_stack) -> None:
    service, _provider, workspace_path, _bus = git_stack
    _run_git(workspace_path, "init")
    _run_git(workspace_path, "config", "user.email", "dev@example.com")
    _run_git(workspace_path, "config", "user.name", "Dev")
    detected = await service.refresh()
    assert detected is not None
    assert detected.root == workspace_path.resolve()


@pytest.mark.asyncio
async def test_commit_requires_message(git_stack) -> None:
    service, _provider, workspace_path, _bus = git_stack
    await service.init()
    (workspace_path / "a.robot").write_text("*** Test Cases ***\nA\n    Log    1\n")
    with pytest.raises(GitValidationError, match="message"):
        await service.commit("   ")


@pytest.mark.asyncio
async def test_history_empty_before_first_commit(tmp_path: Path) -> None:
    provider = CliGitProvider()
    workspace_path = tmp_path / "WS"
    workspace_path.mkdir()
    _run_git(workspace_path, "init")
    history = await provider.history(workspace_path, limit=10)
    assert history == []


@pytest.mark.asyncio
async def test_refresh_on_workspace_opened(git_stack) -> None:
    service, _provider, workspace_path, bus = git_stack
    _run_git(workspace_path, "init")
    await bus.publish(WorkspaceOpened(workspace_id=service.context.workspace.id))
    repository = await service.get_repository()
    assert repository is not None
    assert repository.is_repository is True
