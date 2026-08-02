"""Unit tests for project management."""

from pathlib import Path

import pytest

from robot_studio.application.services.project_service import ProjectService
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.application.services.workspace_service import WorkspaceService
from robot_studio.core.events import (
    InMemoryEventBus,
    ProjectCreated,
    ProjectImported,
    ProjectOpened,
)
from robot_studio.domain.models import ProjectType
from robot_studio.infrastructure.project.filesystem import (
    FilesystemProjectProvider,
    ProjectValidationError,
)
from robot_studio.infrastructure.repositories.project_repository import (
    SqliteProjectRepository,
)
from robot_studio.infrastructure.repositories.workspace_repository import (
    SqliteWorkspaceRepository,
)


@pytest.fixture
async def services(tmp_path: Path):
    db = tmp_path / "test.db"
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)

    workspace_repo = SqliteWorkspaceRepository(db)
    await workspace_repo.initialize()
    workspace_service = WorkspaceService(workspace_repo, context)

    fs = FilesystemProjectProvider()
    project_repo = SqliteProjectRepository(db)
    await project_repo.initialize()
    project_service = ProjectService(
        repository=project_repo,
        context=context,
        event_bus=bus,
        filesystem=fs,
    )

    homes = tmp_path / "homes"
    homes.mkdir()
    workspace = await workspace_service.create_workspace("WS", homes)
    return {
        "bus": bus,
        "context": context,
        "workspace": workspace,
        "project_service": project_service,
        "project_repo": project_repo,
        "fs": fs,
        "tmp_path": tmp_path,
    }


@pytest.mark.asyncio
async def test_create_project_scaffolds_folders_only(services) -> None:
    events: list[object] = []

    async def on_created(event: ProjectCreated) -> None:
        events.append(event)

    async def on_opened(event: ProjectOpened) -> None:
        events.append(event)

    services["bus"].subscribe(ProjectCreated, on_created)
    services["bus"].subscribe(ProjectOpened, on_opened)

    project = await services["project_service"].create_project("Demo")

    assert project.name == "Demo"
    assert project.type == ProjectType.EMPTY
    assert (project.path / "tests").is_dir()
    assert (project.path / "resources").is_dir()
    assert (project.path / "variables").is_dir()
    assert not (project.path / "requirements.txt").exists()
    assert not (project.path / "tests" / "sample.robot").exists()
    assert (project.path / ".robotstudio" / "project.json").is_file()
    gitignore = (project.path / ".gitignore").read_text(encoding="utf-8")
    assert ".robotstudio/" in gitignore
    assert "Environments/" not in gitignore
    assert "Reports/" not in gitignore
    assert services["context"].project_id == project.id
    assert any(isinstance(e, ProjectCreated) for e in events)
    assert any(isinstance(e, ProjectOpened) for e in events)


@pytest.mark.asyncio
async def test_import_project_by_reference(services) -> None:
    external = services["tmp_path"] / "ExternalRobot"
    external.mkdir()
    (external / "requirements.txt").write_text("robotframework\n", encoding="utf-8")
    (external / "suite.robot").write_text(
        "*** Test Cases ***\nDummy\n    No Operation\n",
    )

    events: list[ProjectImported] = []

    async def on_imported(event: ProjectImported) -> None:
        events.append(event)

    services["bus"].subscribe(ProjectImported, on_imported)

    project = await services["project_service"].import_project(external)
    assert project.path == external.resolve()
    assert project.type == ProjectType.IMPORTED
    assert (external / ".robotstudio" / "project.json").is_file()
    assert len(events) == 1

    # Import does not copy into Projects/
    assert not (
        services["workspace"].path / "Projects" / "ExternalRobot"
    ).exists() or (
        services["workspace"].path / "Projects" / "ExternalRobot"
    ).resolve() != external.resolve()


@pytest.mark.asyncio
async def test_import_validation_rejects_non_robot(services) -> None:
    plain = services["tmp_path"] / "plain"
    plain.mkdir()
    (plain / "notes.txt").write_text("hi", encoding="utf-8")

    with pytest.raises(ProjectValidationError, match="does not look like"):
        await services["project_service"].import_project(plain)


@pytest.mark.asyncio
async def test_is_robot_project_markers(tmp_path: Path) -> None:
    fs = FilesystemProjectProvider()
    a = tmp_path / "a"
    a.mkdir()
    (a / "robot.yaml").write_text("tasks: {}\n", encoding="utf-8")
    assert fs.is_robot_project(a)

    b = tmp_path / "b"
    b.mkdir()
    (b / "pyproject.toml").write_text("[project]\nname='x'\n", encoding="utf-8")
    assert fs.is_robot_project(b)


@pytest.mark.asyncio
async def test_recent_projects_ordering(services) -> None:
    first = await services["project_service"].create_project("One")
    second = await services["project_service"].create_project("Two")
    await services["project_service"].open_project(first.id)

    recent = await services["project_service"].list_recent()
    assert [item.name for item in recent[:2]] == ["One", "Two"]
    assert second.name == "Two"


@pytest.mark.asyncio
async def test_list_projects(services) -> None:
    await services["project_service"].create_project("A")
    await services["project_service"].create_project("B")
    projects = await services["project_service"].list_projects()
    assert sorted(p.name for p in projects) == ["A", "B"]


@pytest.mark.asyncio
async def test_legacy_type_normalizes_to_empty() -> None:
    assert ProjectType.normalize("browser") == ProjectType.EMPTY
    assert ProjectType.normalize("api") == ProjectType.EMPTY
    assert ProjectType.normalize("selenium") == ProjectType.EMPTY
    assert ProjectType.normalize("imported") == ProjectType.IMPORTED
    assert ProjectType.normalize("empty") == ProjectType.EMPTY
