"""Unit tests for environment management."""

from pathlib import Path
import sys

import pytest

from robot_studio.application.services.environment_service import EnvironmentService
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.application.services.workspace_service import WorkspaceService
from robot_studio.core.events import (
    EnvironmentActivated,
    EnvironmentCloned,
    EnvironmentCreated,
    EnvironmentDeleted,
    EnvironmentImported,
    InMemoryEventBus,
)
from robot_studio.infrastructure.environment.filesystem import (
    EnvironmentValidationError,
    FilesystemEnvironmentProvider,
)
from robot_studio.infrastructure.environment.python_provider import (
    PythonEnvironmentProvider,
)
from robot_studio.infrastructure.repositories.environment_repository import (
    SqliteEnvironmentRepository,
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

    env_repo = SqliteEnvironmentRepository(db)
    await env_repo.initialize()
    environment_service = EnvironmentService(
        repository=env_repo,
        context=context,
        event_bus=bus,
        filesystem=FilesystemEnvironmentProvider(),
        python=PythonEnvironmentProvider(),
    )

    homes = tmp_path / "homes"
    homes.mkdir()
    workspace = await workspace_service.create_workspace("WS", homes)
    return {
        "bus": bus,
        "context": context,
        "workspace": workspace,
        "environment_service": environment_service,
        "environment_repo": env_repo,
        "tmp_path": tmp_path,
    }


@pytest.mark.asyncio
async def test_create_environment(services) -> None:
    events: list[object] = []

    async def on_created(event: EnvironmentCreated) -> None:
        events.append(event)

    async def on_activated(event: EnvironmentActivated) -> None:
        events.append(event)

    services["bus"].subscribe(EnvironmentCreated, on_created)
    services["bus"].subscribe(EnvironmentActivated, on_activated)

    environment = await services["environment_service"].create_environment(
        "robot-3",
        sys.executable,
        install_robot_framework=False,
    )

    assert environment.name == "robot-3"
    assert ".robotstudio" in Path(environment.path).parts
    assert "environments" in Path(environment.path).parts
    assert (environment.path / "pyvenv.cfg").is_file()
    assert (environment.path / "environment.json").is_file()
    assert environment.python_executable.is_file()
    assert environment.is_active is True
    assert services["context"].environment_id == environment.id
    assert any(isinstance(e, EnvironmentCreated) for e in events)
    assert any(isinstance(e, EnvironmentActivated) for e in events)


@pytest.mark.asyncio
async def test_discover_legacy_environments_root(services) -> None:
    """Existing project-root Environments/ venvs are still discovered."""
    workspace = services["workspace"]
    legacy_root = workspace.path / "Environments" / "legacy-env"
    PythonEnvironmentProvider().create_venv(Path(sys.executable), legacy_root)

    discovered = FilesystemEnvironmentProvider().discover(workspace.path)
    assert any(path.name == "legacy-env" for path in discovered)

    listed = await services["environment_service"].list_environments()
    assert any(item.name == "legacy-env" for item in listed)


@pytest.mark.asyncio
async def test_create_blocks_legacy_name_collision(services) -> None:
    workspace = services["workspace"]
    legacy_root = workspace.path / "Environments" / "taken"
    PythonEnvironmentProvider().create_venv(Path(sys.executable), legacy_root)

    with pytest.raises(EnvironmentValidationError, match="already exists"):
        await services["environment_service"].create_environment(
            "taken",
            sys.executable,
        )
    tmp_path = services["tmp_path"]
    missing = tmp_path / "not-a-venv"
    missing.mkdir()

    with pytest.raises(EnvironmentValidationError, match="pyvenv.cfg"):
        await services["environment_service"].import_environment(missing)

    created = await services["environment_service"].create_environment(
        "primary",
        sys.executable,
    )
    with pytest.raises(EnvironmentValidationError, match="already registered"):
        await services["environment_service"].import_environment(created.path)


@pytest.mark.asyncio
async def test_import_existing_venv(services) -> None:
    events: list[object] = []

    async def on_imported(event: EnvironmentImported) -> None:
        events.append(event)

    services["bus"].subscribe(EnvironmentImported, on_imported)

    external = services["tmp_path"] / "external-venv"
    PythonEnvironmentProvider().create_venv(Path(sys.executable), external)

    imported = await services["environment_service"].import_environment(external)
    assert imported.name == "external-venv"
    assert (imported.path / "environment.json").is_file()
    assert any(isinstance(e, EnvironmentImported) for e in events)


@pytest.mark.asyncio
async def test_activation(services) -> None:
    first = await services["environment_service"].create_environment(
        "first",
        sys.executable,
    )
    second = await services["environment_service"].create_environment(
        "second",
        sys.executable,
    )
    assert first.is_active is True
    assert second.is_active is False

    activated = await services["environment_service"].activate_environment(second.id)
    assert activated.is_active is True
    assert services["context"].environment_id == second.id

    listed = await services["environment_service"].list_environments()
    by_name = {item.name: item for item in listed}
    assert by_name["second"].is_active is True
    assert by_name["first"].is_active is False


@pytest.mark.asyncio
async def test_clone_environment(services) -> None:
    events: list[object] = []

    async def on_cloned(event: EnvironmentCloned) -> None:
        events.append(event)

    services["bus"].subscribe(EnvironmentCloned, on_cloned)

    source = await services["environment_service"].create_environment(
        "source",
        sys.executable,
        install_robot_framework=False,
    )
    cloned = await services["environment_service"].clone_environment(
        source.id,
        "clone",
    )
    assert cloned.name == "clone"
    assert cloned.path != source.path
    assert (cloned.path / "pyvenv.cfg").is_file()
    assert any(isinstance(e, EnvironmentCloned) for e in events)


@pytest.mark.asyncio
async def test_delete_protection(services) -> None:
    events: list[object] = []

    async def on_deleted(event: EnvironmentDeleted) -> None:
        events.append(event)

    services["bus"].subscribe(EnvironmentDeleted, on_deleted)

    active = await services["environment_service"].create_environment(
        "active-env",
        sys.executable,
    )
    other = await services["environment_service"].create_environment(
        "other-env",
        sys.executable,
    )

    with pytest.raises(EnvironmentValidationError, match="active environment"):
        await services["environment_service"].delete_environment(active.id)

    await services["environment_service"].delete_environment(
        other.id,
        delete_files=True,
    )
    assert not other.path.exists()
    assert any(isinstance(e, EnvironmentDeleted) for e in events)

    remaining = await services["environment_service"].list_environments()
    assert len(remaining) == 1
    assert remaining[0].id == active.id


@pytest.mark.asyncio
async def test_install_robot_survives_deleted_process_cwd(services) -> None:
    """Pip calls os.getcwd(); a deleted backend cwd must not break install."""
    import os
    import tempfile

    gone = Path(tempfile.mkdtemp())
    os.chdir(gone)
    gone.rmdir()
    with pytest.raises(FileNotFoundError):
        Path.cwd()

    environment = await services["environment_service"].create_environment(
        "with-robot",
        sys.executable,
        install_robot_framework=True,
    )
    assert environment.robot_version is not None
    assert Path(environment.path).is_dir()


def test_stable_subprocess_cwd_skips_missing_preferred(tmp_path: Path) -> None:
    from robot_studio.infrastructure.environment.python_provider import (
        stable_subprocess_cwd,
    )

    resolved = Path(stable_subprocess_cwd(tmp_path / "does-not-exist"))
    assert resolved.is_dir()


@pytest.mark.asyncio
async def test_missing_venv_marked_unavailable(services) -> None:
    environment = await services["environment_service"].create_environment(
        "gone",
        sys.executable,
    )
    assert environment.available is True
    assert environment.is_active is True

    # Simulate deleting the Environments folder while the DB row remains.
    import shutil

    shutil.rmtree(environment.path)
    listed = await services["environment_service"].list_environments()
    assert len(listed) == 1
    assert listed[0].id == environment.id
    assert listed[0].is_active is True
    assert listed[0].available is False


@pytest.mark.asyncio
async def test_reopen_purges_missing_environments(services) -> None:
    """Recreating a project at the same path must not revive ghost envs."""
    import shutil

    from robot_studio.infrastructure.workspace.filesystem import (
        create_workspace_structure,
    )

    environment = await services["environment_service"].create_environment(
        "ghost",
        sys.executable,
    )
    workspace = services["workspace"]
    workspace_path = workspace.path
    workspace_id = workspace.id

    shutil.rmtree(environment.path)
    assert not environment.path.is_dir()

    # Mid-session list still surfaces the missing row.
    listed = await services["environment_service"].list_environments()
    assert len(listed) == 1
    assert listed[0].available is False

    # Simulate Finder delete + recreate at the same absolute path (same uuid5 id).
    shutil.rmtree(workspace_path)
    create_workspace_structure(workspace_path, "WS")

    services["environment_service"].start()
    workspace_repo = SqliteWorkspaceRepository(services["tmp_path"] / "test.db")
    await workspace_repo.initialize()
    workspace_service = WorkspaceService(workspace_repo, services["context"])
    reopened = await workspace_service.open_workspace(workspace_path)
    assert reopened.id == workspace_id

    remaining = await services["environment_repo"].list_by_workspace(workspace_id)
    assert remaining == []
    listed_after = await services["environment_service"].list_environments()
    assert listed_after == []


@pytest.mark.asyncio
async def test_purge_workspace_environments_clears_registry(services) -> None:
    environment = await services["environment_service"].create_environment(
        "to-clear",
        sys.executable,
    )
    workspace_id = services["workspace"].id
    removed = await services["environment_service"].purge_workspace_environments(
        workspace_id,
    )
    assert removed >= 1
    assert await services["environment_repo"].get(environment.id) is None
    assert services["context"].environment is None


@pytest.mark.asyncio
async def test_repository_persistence(services) -> None:
    created = await services["environment_service"].create_environment(
        "persist",
        sys.executable,
    )
    loaded = await services["environment_repo"].get(created.id)
    assert loaded is not None
    assert loaded.name == "persist"
    assert loaded.python_version
    assert loaded.python_executable.is_file()
