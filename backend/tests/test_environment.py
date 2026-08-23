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
async def test_import_dot_venv_uses_sanitized_name(services) -> None:
    """Project-local ``.venv`` is offered as ``venv`` and must import cleanly."""
    project_venv = services["workspace"].path / ".venv"
    PythonEnvironmentProvider().create_venv(Path(sys.executable), project_venv)

    detected = await services["environment_service"].detect_candidate_environments()
    by_path = {item["path"]: item["name"] for item in detected}
    assert by_path[str(project_venv.resolve())] == "venv"

    imported = await services["environment_service"].import_environment(project_venv)
    assert imported.name == "venv"
    assert imported.path.resolve() == project_venv.resolve()


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
@pytest.mark.skipif(
    sys.platform == "win32",
    reason="Windows refuses to delete a directory that is the process cwd",
)
async def test_install_robot_survives_deleted_process_cwd(services) -> None:
    """Pip calls os.getcwd(); a deleted backend cwd must not break install.

    The destroyed cwd is process-global; the autouse ``_restore_process_cwd``
    fixture puts it back so later tests can still spawn subprocesses.
    """
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


@pytest.mark.skipif(sys.platform == "win32", reason="venv python is a symlink on Unix")
def test_resolve_executables_keeps_venv_python_wrapper(tmp_path: Path) -> None:
    """Following the symlink would pip-install into system Python (PEP 668)."""
    from robot_studio.infrastructure.environment.python_provider import (
        PythonEnvironmentProvider,
    )

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    wrapper = bin_dir / "python"
    wrapper.symlink_to(sys.executable)
    (tmp_path / "pyvenv.cfg").write_text("home = /\n", encoding="utf-8")

    resolved = PythonEnvironmentProvider().resolve_executables(tmp_path)
    assert resolved.python == wrapper.absolute()
    assert resolved.python != Path(sys.executable).resolve()


def test_discover_interpreters_finds_host_python() -> None:
    from robot_studio.infrastructure.environment.python_provider import (
        PythonEnvironmentProvider,
        _is_bundled_sidecar,
    )

    assert _is_bundled_sidecar(Path("robot-studio-backend.exe"))
    assert _is_bundled_sidecar(Path("/tmp/robot-studio-backend"))
    assert not _is_bundled_sidecar(Path(sys.executable))

    found = PythonEnvironmentProvider().discover_interpreters()
    assert any(Path(item.path).exists() for item in found)
    assert all("robot-studio-backend" not in item.path.lower() for item in found)


def test_host_python_subprocess_env_strips_bundle_vars_when_frozen(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from robot_studio.infrastructure.environment.python_provider import (
        _host_python_subprocess_env,
    )

    monkeypatch.setenv("LD_LIBRARY_PATH", "/app/backend/_internal")
    monkeypatch.setenv("LD_PRELOAD", "/tmp/evil.so")
    monkeypatch.setenv("PYTHONHOME", "/wrong")
    monkeypatch.setattr(sys, "frozen", True, raising=False)

    env = _host_python_subprocess_env()
    assert "LD_LIBRARY_PATH" not in env
    assert "LD_PRELOAD" not in env
    assert "PYTHONHOME" not in env


def test_host_python_subprocess_env_keeps_vars_when_not_frozen(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from robot_studio.infrastructure.environment.python_provider import (
        _host_python_subprocess_env,
    )

    monkeypatch.setenv("LD_LIBRARY_PATH", "/custom/lib")
    monkeypatch.setattr(sys, "frozen", False, raising=False)

    env = _host_python_subprocess_env()
    assert env.get("LD_LIBRARY_PATH") == "/custom/lib"


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
async def test_recreate_same_name_after_folder_delete_activates_new(services) -> None:
    """edgecase #9: Create A, delete folder, Create B same name — B active, A gone."""
    import shutil

    a = await services["environment_service"].create_environment(
        "venv",
        sys.executable,
    )
    assert a.is_active is True
    old_id = a.id
    shutil.rmtree(a.path)

    listed = await services["environment_service"].list_environments()
    assert len(listed) == 1
    assert listed[0].available is False
    assert listed[0].is_active is True

    b = await services["environment_service"].create_environment(
        "venv",
        sys.executable,
    )
    assert b.id != old_id
    assert b.name == "venv"
    assert b.available is True
    assert b.is_active is True
    assert services["context"].environment_id == b.id

    listed_after = await services["environment_service"].list_environments()
    assert len(listed_after) == 1
    assert listed_after[0].id == b.id
    assert listed_after[0].is_active is True
    assert listed_after[0].available is True
    assert await services["environment_repo"].get(old_id) is None


@pytest.mark.asyncio
async def test_recreate_same_path_gets_new_identity(services) -> None:
    """Delete + recreate at the same path must mint a new durable identity."""
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
    old_workspace_id = workspace.id

    shutil.rmtree(environment.path)
    assert not environment.path.is_dir()

    # Mid-session list still surfaces the missing row for the open identity.
    listed = await services["environment_service"].list_environments()
    assert len(listed) == 1
    assert listed[0].available is False

    shutil.rmtree(workspace_path)
    create_workspace_structure(workspace_path, "WS")

    services["environment_service"].start()
    workspace_repo = SqliteWorkspaceRepository(services["tmp_path"] / "test.db")
    await workspace_repo.initialize()
    workspace_service = WorkspaceService(workspace_repo, services["context"])
    reopened = await workspace_service.open_workspace(workspace_path)
    assert reopened.id != old_workspace_id

    # New identity has no environments; old rows may orphan under the old id.
    listed_after = await services["environment_service"].list_environments()
    assert listed_after == []
    assert await services["environment_repo"].list_by_workspace(reopened.id) == []


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
