"""Unit tests for workspace creation, validation, and recent list."""

from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.application.services.workspace_service import WorkspaceService
from robot_studio.core.events import InMemoryEventBus, WorkspaceOpened
from robot_studio.domain.models import Workspace
from robot_studio.infrastructure.repositories.workspace_repository import (
    SqliteWorkspaceRepository,
)
from robot_studio.infrastructure.workspace.filesystem import (
    STANDARD_DIRECTORIES,
    WorkspaceValidationError,
    create_workspace_structure,
    is_workspace,
    load_manifest,
    manifest_path,
    studio_environments_root,
    studio_reports_root,
)


@pytest.fixture
async def repository(tmp_path: Path) -> SqliteWorkspaceRepository:
    db_path = tmp_path / "test.db"
    repo = SqliteWorkspaceRepository(db_path)
    await repo.initialize()
    return repo


@pytest.fixture
def event_bus() -> InMemoryEventBus:
    return InMemoryEventBus()


@pytest.fixture
def context(event_bus: InMemoryEventBus) -> WorkspaceContext:
    return WorkspaceContext(event_bus)


@pytest.fixture
def service(
    repository: SqliteWorkspaceRepository,
    context: WorkspaceContext,
) -> WorkspaceService:
    return WorkspaceService(repository=repository, context=context)


@pytest.mark.asyncio
async def test_create_workspace_structure(tmp_path: Path) -> None:
    root = tmp_path / "Demo"
    manifest = create_workspace_structure(root, "Demo")

    assert manifest.name == "Demo"
    assert manifest.version == 1
    assert manifest.id is not None
    assert manifest.projects == []
    assert is_workspace(root)
    assert manifest_path(root).is_file()

    for relative in STANDARD_DIRECTORIES:
        assert (root / relative).is_dir()

    assert studio_environments_root(root).is_dir()
    assert studio_reports_root(root).is_dir()
    assert not (root / "Environments").exists()
    assert not (root / "Reports").exists()

    loaded = load_manifest(root)
    assert loaded.name == "Demo"
    assert loaded.id == manifest.id
    assert loaded.projects == []


@pytest.mark.asyncio
async def test_create_workspace_rejects_nonempty_directory(tmp_path: Path) -> None:
    root = tmp_path / "Occupied"
    root.mkdir()
    (root / "notes.txt").write_text("hello", encoding="utf-8")

    with pytest.raises(WorkspaceValidationError, match="not empty"):
        create_workspace_structure(root, "Occupied")


@pytest.mark.asyncio
async def test_create_workspace_service(
    service: WorkspaceService,
    context: WorkspaceContext,
    event_bus: InMemoryEventBus,
    tmp_path: Path,
) -> None:
    opened: list[WorkspaceOpened] = []

    async def on_opened(event: WorkspaceOpened) -> None:
        opened.append(event)

    event_bus.subscribe(WorkspaceOpened, on_opened)

    workspace = await service.create_workspace("Alpha", tmp_path)

    assert workspace.name == "Alpha"
    assert workspace.path == tmp_path / "Alpha"
    assert is_workspace(workspace.path)
    assert context.is_open
    assert context.workspace_id == workspace.id
    assert len(opened) == 1


@pytest.mark.asyncio
async def test_open_workspace_validates_manifest(
    service: WorkspaceService,
    tmp_path: Path,
) -> None:
    with pytest.raises(WorkspaceValidationError, match="not a Robot Studio workspace"):
        await service.open_workspace(tmp_path)


@pytest.mark.asyncio
async def test_open_workspace_success(
    service: WorkspaceService,
    context: WorkspaceContext,
    tmp_path: Path,
) -> None:
    created = await service.create_workspace("Beta", tmp_path)
    await context.close()

    opened = await service.open_workspace(created.path)
    assert opened.id == created.id
    assert opened.name == "Beta"
    assert context.workspace_id == opened.id


@pytest.mark.asyncio
async def test_recent_workspaces_ordering_and_dedupe(
    repository: SqliteWorkspaceRepository,
    tmp_path: Path,
) -> None:
    first_root = tmp_path / "One"
    second_root = tmp_path / "Two"
    create_workspace_structure(first_root, "One")
    create_workspace_structure(second_root, "Two")

    one = Workspace(
        id=uuid4(),
        name="One",
        path=first_root,
        created_at=datetime.now(UTC),
    )
    two = Workspace(
        id=uuid4(),
        name="Two",
        path=second_root,
        created_at=datetime.now(UTC),
    )

    await repository.create(one)
    await repository.create(two)
    await repository.record_recent(one)
    await repository.record_recent(two)
    await repository.record_recent(one)

    recent = await repository.list_recent()
    assert [item.name for item in recent] == ["One", "Two"]


@pytest.mark.asyncio
async def test_recent_ignores_missing_directories(
    repository: SqliteWorkspaceRepository,
    tmp_path: Path,
) -> None:
    alive_root = tmp_path / "Alive"
    dead_root = tmp_path / "Dead"
    create_workspace_structure(alive_root, "Alive")
    create_workspace_structure(dead_root, "Dead")

    alive = Workspace(
        id=uuid4(),
        name="Alive",
        path=alive_root,
        created_at=datetime.now(UTC),
    )
    dead = Workspace(
        id=uuid4(),
        name="Dead",
        path=dead_root,
        created_at=datetime.now(UTC),
    )

    await repository.create(alive)
    await repository.create(dead)
    await repository.record_recent(alive)
    await repository.record_recent(dead)

    # Remove the directory after recording
    import shutil

    shutil.rmtree(dead_root)

    recent = await repository.list_recent()
    assert [item.name for item in recent] == ["Alive"]


@pytest.mark.asyncio
async def test_service_list_recent_filters_invalid_workspaces(
    service: WorkspaceService,
    repository: SqliteWorkspaceRepository,
    tmp_path: Path,
) -> None:
    created = await service.create_workspace("Gamma", tmp_path)

    # Corrupt by removing marker while keeping the folder
    manifest_path(created.path).unlink()

    recent = await service.list_recent()
    assert recent == []


@pytest.mark.asyncio
async def test_project_folder_opens_are_not_recent_workspaces(
    service: WorkspaceService,
    tmp_path: Path,
) -> None:
    from robot_studio.infrastructure.workspace.filesystem import (
        initialize_project_as_workspace,
    )

    classic = await service.create_workspace("ClassicWS", tmp_path)
    project_root = tmp_path / "MySuite"
    project_root.mkdir()
    initialize_project_as_workspace(project_root, "MySuite")
    await service.open_workspace(project_root)

    recent = await service.list_recent()
    assert [item.name for item in recent] == ["ClassicWS"]
    assert classic.path in {item.path for item in recent}
    assert project_root.resolve() not in {item.path.resolve() for item in recent}


@pytest.mark.asyncio
async def test_repository_get_by_path(
    repository: SqliteWorkspaceRepository,
    tmp_path: Path,
) -> None:
    root = tmp_path / "Delta"
    create_workspace_structure(root, "Delta")
    workspace = Workspace(
        id=uuid4(),
        name="Delta",
        path=root,
        created_at=datetime.now(UTC),
    )
    await repository.create(workspace)

    found = await repository.get_by_path(root)
    assert found is not None
    assert found.id == workspace.id
    assert await repository.get(workspace.id) is not None


@pytest.mark.asyncio
async def test_durable_id_survives_folder_move(
    service: WorkspaceService,
    repository: SqliteWorkspaceRepository,
    tmp_path: Path,
) -> None:
    created = await service.create_workspace("Movable", tmp_path)
    original_id = created.id
    old_path = created.path
    new_path = tmp_path / "Moved"
    old_path.rename(new_path)

    reopened = await service.open_workspace(new_path)
    assert reopened.id == original_id
    assert reopened.path == new_path.resolve()

    by_id = await repository.get(original_id)
    assert by_id is not None
    assert by_id.path == new_path.resolve()
    assert await repository.get_by_path(old_path) is None


@pytest.mark.asyncio
async def test_migrate_on_read_reuses_project_id_for_standalone(
    service: WorkspaceService,
    tmp_path: Path,
) -> None:
    """Legacy workspace.json without id picks up project.json id on open."""
    import json
    from uuid import uuid4

    from robot_studio.infrastructure.project.filesystem import (
        FilesystemProjectProvider,
    )
    from robot_studio.domain.models import ProjectType

    root = tmp_path / "Legacy"
    root.mkdir()
    meta = root / ".robotstudio"
    meta.mkdir()
    project_id = uuid4()
    (meta / "workspace.json").write_text(
        json.dumps(
            {
                "name": "Legacy",
                "version": 1,
                "created_at": datetime.now(UTC).isoformat(),
                "projects": [],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    fs = FilesystemProjectProvider()
    fs.write_manifest(
        root,
        fs.create_manifest(
            name="Legacy",
            project_type=ProjectType.EMPTY,
            project_id=project_id,
        ),
    )

    opened = await service.open_workspace(root)
    assert opened.id == project_id
    assert load_manifest(root).id == project_id


@pytest.mark.asyncio
async def test_recreate_same_path_mints_new_workspace_id(
    service: WorkspaceService,
    tmp_path: Path,
) -> None:
    import shutil

    created = await service.create_workspace("Fresh", tmp_path)
    old_id = created.id
    path = created.path
    shutil.rmtree(path)
    create_workspace_structure(path, "Fresh")
    reopened = await service.open_workspace(path)
    assert reopened.id != old_id
    assert load_manifest(path).id == reopened.id