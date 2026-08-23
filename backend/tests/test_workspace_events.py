"""Tier-1 live workspace event stream tests."""

from __future__ import annotations

import asyncio
import shutil
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.core.container import Container
from robot_studio.core.events import FilesystemChanged, IndexUpdated, RepositoryUpdated
from robot_studio.domain.models import Project, ProjectType, Workspace
from robot_studio.infrastructure.indexing.file_watcher import PollingFileWatcher


@pytest.fixture
async def live_stack(tmp_path: Path):
    container = Container()
    container.initialize()
    assert container.workspace_context is not None
    assert container.workspace_event_service is not None

    workspace = Workspace(
        id=uuid4(),
        name="Live",
        path=tmp_path,
        created_at=datetime.now(UTC),
    )
    await container.workspace_context.open(workspace)
    try:
        yield container, tmp_path
    finally:
        await container.shutdown()


@pytest.mark.asyncio
async def test_filesystem_changed_broadcasts_file_and_git_events(live_stack) -> None:
    container, root = live_stack
    service = container.workspace_event_service
    assert service is not None
    queue = await service.subscribe()

    await container.event_bus.publish(
        FilesystemChanged(
            kind="FILE_MODIFIED",
            path=str(root / "tests" / "a.robot"),
            is_directory=False,
        )
    )

    first = await asyncio.wait_for(queue.get(), timeout=2)
    second = await asyncio.wait_for(queue.get(), timeout=2)
    types = {first["type"], second["type"]}
    assert "FILE_MODIFIED" in types
    assert "GIT_CHANGED" in types
    await service.unsubscribe(queue)


@pytest.mark.asyncio
async def test_index_and_repo_events_map_to_wire_types(live_stack) -> None:
    container, root = live_stack
    service = container.workspace_event_service
    assert service is not None
    queue = await service.subscribe()

    await container.event_bus.publish(IndexUpdated(scope="file", scope_id="/x.robot"))
    index_msg = await asyncio.wait_for(queue.get(), timeout=2)
    assert index_msg["type"] == "INDEX_UPDATED"
    assert index_msg["scope"] == "file"

    await container.event_bus.publish(RepositoryUpdated(root=str(root)))
    git_msg = await asyncio.wait_for(queue.get(), timeout=2)
    assert git_msg["type"] == "GIT_CHANGED"
    await service.unsubscribe(queue)


@pytest.mark.asyncio
async def test_missing_project_emits_project_changed(live_stack) -> None:
    container, root = live_stack
    service = container.workspace_event_service
    assert service is not None
    ctx = container.workspace_context
    assert ctx is not None
    assert ctx.workspace_id is not None

    project_dir = root / "gone-project"
    project_dir.mkdir()
    project = Project(
        id=uuid4(),
        workspace_id=ctx.workspace_id,
        name="Gone",
        path=project_dir,
        type=ProjectType.EMPTY,
        created_at=datetime.now(UTC),
    )
    await ctx.set_active_project(project)
    project_dir.rmdir()

    queue = await service.subscribe()
    await service._on_watcher_fs_change(
        "deleted",
        project_dir,
        is_dir=True,
    )
    messages = []
    for _ in range(6):
        try:
            messages.append(await asyncio.wait_for(queue.get(), timeout=0.5))
        except TimeoutError:
            break
    assert any(
        item.get("type") == "PROJECT_CHANGED" and item.get("reason") == "missing"
        for item in messages
    )
    await service.unsubscribe(queue)


@pytest.mark.asyncio
async def test_deleted_workspace_root_detected_without_fs_events(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Deleting the watched root emits no watcher events — the poll must catch it."""
    from robot_studio.core.config import settings

    monkeypatch.setattr(settings, "data_dir", tmp_path / "data")
    settings.data_dir.mkdir(parents=True, exist_ok=True)

    container = Container()
    await container.initialize_async()
    service = container.workspace_event_service
    assert service is not None
    service.root_poll_seconds = 0.05

    root = tmp_path / "Standalone"
    root.mkdir()
    workspace = Workspace(
        id=uuid4(),
        name="Standalone",
        path=root,
        created_at=datetime.now(UTC),
    )
    try:
        assert container.workspace_context is not None
        await container.workspace_context.open(workspace)
        queue = await service.subscribe()
        shutil.rmtree(root)

        missing = None
        deadline = asyncio.get_running_loop().time() + 3
        while asyncio.get_running_loop().time() < deadline:
            message = await asyncio.wait_for(queue.get(), timeout=3)
            if message.get("reason") == "missing":
                missing = message
                break
        assert missing is not None, "no missing event emitted for deleted root"
        assert missing["type"] == "WORKSPACE_CHANGED"
        assert missing["path"] == str(root)
        # Session must be cleared so subsequent create/open is not stuck on
        # the deleted path.
        assert container.workspace_context is not None
        assert container.workspace_context.workspace is None
        await service.unsubscribe(queue)
    finally:
        await container.shutdown()

@pytest.mark.asyncio
async def test_polling_watcher_emits_fs_and_index_channels(tmp_path: Path) -> None:
    watcher = PollingFileWatcher(interval_seconds=0.05)
    fs_events: list[tuple] = []
    index_events: list[tuple] = []

    async def on_fs(event, path, *, is_dir=False, dest_path=None):
        fs_events.append((event, path.name, is_dir))

    async def on_change(event, path):
        index_events.append((event, path.name))

    watcher.on_fs_change = on_fs
    watcher.on_change = on_change
    watcher.watch_path(tmp_path)
    await watcher.start()
    try:
        robot = tmp_path / "suite.robot"
        robot.write_text("*** Test Cases ***\nA\n    No Operation\n")
        md = tmp_path / "readme.md"
        md.write_text("hi")
        await asyncio.sleep(0.25)
        assert any(item[0] == "created" and item[1] == "suite.robot" for item in fs_events)
        assert any(item[0] == "created" and item[1] == "readme.md" for item in fs_events)
        assert any(item[0] == "created" and item[1] == "suite.robot" for item in index_events)
        assert not any(item[1] == "readme.md" for item in index_events)
    finally:
        await watcher.stop()


@pytest.mark.asyncio
async def test_container_wires_workspace_event_service() -> None:
    container = Container()
    container.initialize()
    try:
        assert container.workspace_event_service is not None
        queue = await container.workspace_event_service.subscribe()
        await container.workspace_event_service.unsubscribe(queue)
    finally:
        await container.shutdown()
