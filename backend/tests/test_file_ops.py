"""FileService mutation and validation tests."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.application.services.file_service import FileService, FileValidationError
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import FilesystemChanged, InMemoryEventBus
from robot_studio.domain.models import Workspace


@pytest.fixture
async def file_stack(tmp_path: Path):
    bus = InMemoryEventBus()
    ctx = WorkspaceContext(bus)
    workspace = Workspace(
        id=uuid4(),
        name="Files",
        path=tmp_path,
        created_at=datetime.now(UTC),
    )
    await ctx.open(workspace)
    service = FileService(context=ctx, event_bus=bus)
    events: list[FilesystemChanged] = []

    async def on_fs(event: FilesystemChanged) -> None:
        events.append(event)

    bus.subscribe(FilesystemChanged, on_fs)
    return service, tmp_path, events


@pytest.mark.asyncio
async def test_create_file_and_folder(file_stack) -> None:
    service, root, events = file_stack
    created = await service.create_file(str(root / "tests" / "Login.robot"), "")
    assert Path(created["path"]).is_file()
    folder = await service.create_directory(str(root / "resources" / "shared"))
    assert Path(folder["path"]).is_dir()
    kinds = [item.kind for item in events]
    assert "FILE_CREATED" in kinds
    assert "DIRECTORY_CREATED" in kinds


@pytest.mark.asyncio
async def test_rename_delete_duplicate(file_stack) -> None:
    service, root, events = file_stack
    path = root / "a.robot"
    path.write_text("*** Test Cases ***\n")
    renamed = await service.rename_path(str(path), "b.robot")
    assert Path(renamed["path"]).name == "b.robot"
    assert not path.exists()

    # Enter without changing the name must not raise "already exists".
    same = await service.rename_path(renamed["path"], "b.robot")
    assert Path(same["path"]).name == "b.robot"
    assert Path(same["path"]).is_file()

    dup = await service.duplicate_path(renamed["path"])
    assert Path(dup["path"]).name == "b copy.robot"

    deleted = await service.delete_path(dup["path"])
    assert deleted["deleted"] is True
    assert not Path(dup["path"]).exists()


@pytest.mark.asyncio
async def test_move_and_validation(file_stack) -> None:
    service, root, _events = file_stack
    folder = root / "dest"
    folder.mkdir()
    source = root / "move.me"
    source.write_text("x")
    moved = await service.move_path(str(source), str(folder))
    assert Path(moved["path"]) == folder / "move.me"

    with pytest.raises(FileValidationError):
        FileService.validate_entry_name("")
    with pytest.raises(FileValidationError):
        FileService.validate_entry_name("bad/name")
    with pytest.raises(FileValidationError):
        FileService.validate_entry_name("CON")
    with pytest.raises(FileValidationError):
        await service.create_file(str(folder / "move.me"))
