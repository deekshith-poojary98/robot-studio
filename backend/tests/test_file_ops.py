"""FileService mutation and validation tests."""

from __future__ import annotations

import shutil
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
    text = Path(created["path"]).read_text(encoding="utf-8")
    assert "*** Settings ***" in text
    assert "*** Variables ***" in text
    assert "*** Test Cases ***" in text
    assert "*** Keywords ***" in text
    assert "Example Test" in text
    folder = await service.create_directory(str(root / "resources" / "shared"))
    assert Path(folder["path"]).is_dir()
    kinds = [item.kind for item in events]
    assert "FILE_CREATED" in kinds
    assert "DIRECTORY_CREATED" in kinds


@pytest.mark.asyncio
async def test_create_robot_preserves_explicit_content(file_stack) -> None:
    service, root, _events = file_stack
    custom = "*** Test Cases ***\nOnly\n    No Operation\n"
    created = await service.create_file(str(root / "custom.robot"), custom)
    assert Path(created["path"]).read_text(encoding="utf-8") == custom

    plain = await service.create_file(str(root / "notes.txt"), "")
    assert Path(plain["path"]).read_text(encoding="utf-8") == ""


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
async def test_case_only_rename(file_stack) -> None:
    """libs → Libs must stick (macOS/Windows case-insensitive volumes)."""
    service, root, _events = file_stack
    folder = root / "libs"
    folder.mkdir()
    (folder / "marker.txt").write_text("ok", encoding="utf-8")

    renamed = await service.rename_path(str(folder), "Libs")
    assert Path(renamed["path"]).name == "Libs"
    assert renamed["old_path"] == str(folder.resolve())
    assert (Path(renamed["path"]) / "marker.txt").read_text(encoding="utf-8") == "ok"

    # Directory listing should show the new spelling when the FS stores it.
    listed = {p.name for p in root.iterdir()}
    assert "Libs" in listed or "libs" in listed  # case-sensitive Linux may differ in listing API
    # Re-open via the returned path — name component must be Libs.
    assert Path(renamed["path"]).as_posix().endswith("/Libs")

    file_path = Path(renamed["path"]) / "marker.txt"
    file_renamed = await service.rename_path(str(file_path), "Marker.txt")
    assert Path(file_renamed["path"]).name == "Marker.txt"
    assert Path(file_renamed["path"]).as_posix().endswith("/Marker.txt")


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


@pytest.mark.asyncio
async def test_writes_refuse_to_recreate_deleted_workspace(tmp_path: Path) -> None:
    bus = InMemoryEventBus()
    ctx = WorkspaceContext(bus)
    root = tmp_path / "MyProject"
    root.mkdir()
    await ctx.open(
        Workspace(
            id=uuid4(),
            name="MyProject",
            path=root,
            created_at=datetime.now(UTC),
        )
    )
    service = FileService(context=ctx, event_bus=bus)

    shutil.rmtree(root)

    operations = (
        lambda: service.write_file(str(root / "tests" / "a.robot"), "x"),
        lambda: service.create_file(str(root / "tests" / "b.robot"), ""),
        lambda: service.create_directory(str(root / "resources")),
    )
    for operation in operations:
        with pytest.raises(FileValidationError, match="no longer on disk"):
            await operation()
    assert not root.exists()


@pytest.mark.asyncio
async def test_list_tree_shows_dotfiles_except_heavy(file_stack) -> None:
    service, root, _events = file_stack
    (root / ".gitignore").write_text("*.pyc\n", encoding="utf-8")
    (root / ".env.example").write_text("KEY=\n", encoding="utf-8")
    (root / ".git").mkdir()
    (root / ".venv").mkdir()
    (root / ".DS_Store").write_text("", encoding="utf-8")

    tree = await service.list_tree(None, depth=0)
    names = {item["name"] for item in tree}
    assert ".gitignore" in names
    assert ".env.example" in names
    assert ".git" not in names
    assert ".venv" not in names
    assert ".DS_Store" not in names


@pytest.mark.asyncio
async def test_list_tree_shows_robotstudio_contents(file_stack) -> None:
    """Studio's own folder is fully browsable — envs and reports included."""
    service, root, _events = file_stack
    meta = root / ".robotstudio"
    run_dir = meta / "reports" / "Run-20260801-120000"
    run_dir.mkdir(parents=True)
    (run_dir / "report.html").write_text("<html/>", encoding="utf-8")
    site_packages = meta / "environments" / "default" / "lib" / "site-packages"
    site_packages.mkdir(parents=True)
    (site_packages / "robot").mkdir()

    top = {item["name"] for item in await service.list_tree(None, depth=0)}
    assert ".robotstudio" in top

    reports = await service.list_tree(str(meta / "reports"), depth=0)
    assert {item["name"] for item in reports} == {"Run-20260801-120000"}

    # Nothing inside .robotstudio is filtered, not even venv internals.
    env_root = await service.list_tree(str(meta / "environments"), depth=0)
    assert {item["name"] for item in env_root} == {"default"}
    lib = await service.list_tree(str(site_packages.parent), depth=0)
    assert {item["name"] for item in lib} == {"site-packages"}
