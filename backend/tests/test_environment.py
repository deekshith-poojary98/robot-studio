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
    assert (environment.path / "pyvenv.cfg").is_file()
    assert (environment.path / "environment.json").is_file()
    assert environment.python_executable.is_file()
    assert environment.is_active is True
    assert services["context"].environment_id == environment.id
    assert any(isinstance(e, EnvironmentCreated) for e in events)
    assert any(isinstance(e, EnvironmentActivated) for e in events)


@pytest.mark.asyncio
async def test_import_validation(services) -> None:
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
