"""Unit tests for Robot Framework execution."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path
from uuid import UUID

import pytest
from robot_studio.application.services.environment_service import EnvironmentService
from robot_studio.application.services.execution_service import (
    ExecutionService,
    ExecutionValidationError,
)
from robot_studio.application.services.project_service import ProjectService
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.application.services.workspace_service import WorkspaceService
from robot_studio.core.events import (
    ExecutionCancelled,
    ExecutionFinished,
    ExecutionOutput,
    ExecutionStarted,
    InMemoryEventBus,
)
from robot_studio.domain.models import ExecutionStatus
from robot_studio.infrastructure.environment.filesystem import (
    FilesystemEnvironmentProvider,
)
from robot_studio.infrastructure.environment.python_provider import (
    PythonEnvironmentProvider,
)
from robot_studio.infrastructure.execution.results_store import FilesystemResultsStore
from robot_studio.infrastructure.execution.subprocess_runner import SubprocessRunner
from robot_studio.infrastructure.project.filesystem import FilesystemProjectProvider
from robot_studio.infrastructure.repositories.environment_repository import (
    SqliteEnvironmentRepository,
)
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
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

    project_repo = SqliteProjectRepository(db)
    await project_repo.initialize()
    project_service = ProjectService(
        repository=project_repo,
        context=context,
        event_bus=bus,
        filesystem=FilesystemProjectProvider(),
    )

    env_repo = SqliteEnvironmentRepository(db)
    await env_repo.initialize()
    environment_service = EnvironmentService(
        repository=env_repo,
        context=context,
        event_bus=bus,
        filesystem=FilesystemEnvironmentProvider(),
        python=PythonEnvironmentProvider(),
    )

    exec_repo = SqliteExecutionRepository(db)
    await exec_repo.initialize()
    execution_service = ExecutionService(
        context=context,
        event_bus=bus,
        runner=SubprocessRunner(),
        results_store=FilesystemResultsStore(),
        repository=exec_repo,
    )

    homes = tmp_path / "homes"
    homes.mkdir()
    await workspace_service.create_workspace("WS", homes)
    await environment_service.create_environment(
        "robot-env",
        sys.executable,
        install_robot_framework=True,
    )
    project = await project_service.create_project("Demo")
    suite = project.path / "tests" / "sample.robot"
    suite.write_text(
        "*** Test Cases ***\nHello\n    Log    hello from robot\n",
        encoding="utf-8",
    )

    return {
        "bus": bus,
        "context": context,
        "execution_service": execution_service,
        "exec_repo": exec_repo,
        "project": project,
        "suite": suite,
        "tmp_path": tmp_path,
    }


async def _wait_until_done(service: ExecutionService, timeout: float = 60.0) -> None:
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        status = await service.get_status()
        if status is not None and status.status in {
            ExecutionStatus.FINISHED,
            ExecutionStatus.FAILED,
            ExecutionStatus.CANCELLED,
        }:
            return
        await asyncio.sleep(0.1)
    raise TimeoutError("Execution did not finish in time")


@pytest.mark.asyncio
async def test_runner_lifecycle(services) -> None:
    events: list[object] = []

    async def on_started(event: ExecutionStarted) -> None:
        events.append(event)

    async def on_output(event: ExecutionOutput) -> None:
        events.append(event)

    async def on_finished(event: ExecutionFinished) -> None:
        events.append(event)

    services["bus"].subscribe(ExecutionStarted, on_started)
    services["bus"].subscribe(ExecutionOutput, on_output)
    services["bus"].subscribe(ExecutionFinished, on_finished)

    run = await services["execution_service"].run_file(str(services["suite"]))
    assert run.status == ExecutionStatus.RUNNING
    await _wait_until_done(services["execution_service"])

    final = await services["execution_service"].get_status()
    assert final is not None
    assert final.status == ExecutionStatus.FINISHED
    assert final.exit_code == 0
    assert final.output_xml is not None
    assert final.output_xml.is_file()
    assert any(isinstance(e, ExecutionStarted) for e in events)
    assert any(isinstance(e, ExecutionOutput) for e in events)
    assert any(isinstance(e, ExecutionFinished) for e in events)
    progress = [
        e.line
        for e in events
        if isinstance(e, ExecutionOutput) and e.line and e.line.startswith("###RS###|now|")
    ]
    assert any("|Hello|" in line or line.endswith("|Hello|BuiltIn.Log") for line in progress)


@pytest.mark.asyncio
async def test_run_project(services) -> None:
    run = await services["execution_service"].run_project()
    assert run.status == ExecutionStatus.RUNNING
    await _wait_until_done(services["execution_service"])
    final = await services["execution_service"].get_status()
    assert final is not None
    assert final.status == ExecutionStatus.FINISHED


@pytest.mark.asyncio
async def test_run_file_includes_parent_init_suite_setup(services) -> None:
    """A nested file run must still execute tests/__init__.robot Suite Setup."""
    project = services["project"]
    tests = project.path / "tests"
    nested = tests / "posts"
    nested.mkdir()
    (tests / "__init__.robot").write_text(
        "*** Settings ***\n"
        "Suite Setup       Set Global Variable    ${SESSION}    api\n",
        encoding="utf-8",
    )
    suite = nested / "posts_api.robot"
    suite.write_text(
        "*** Test Cases ***\n"
        "Uses Parent Session\n"
        "    Should Be Equal    ${SESSION}    api\n",
        encoding="utf-8",
    )

    run = await services["execution_service"].run_file(str(suite))
    assert run.status == ExecutionStatus.RUNNING
    assert "--suite" in (run.command or "")
    assert "Tests.Posts.Posts Api" in (run.command or "")
    await _wait_until_done(services["execution_service"])
    final = await services["execution_service"].get_status()
    assert final is not None
    assert final.status == ExecutionStatus.FINISHED
    assert final.exit_code == 0


@pytest.mark.asyncio
async def test_cancellation(services) -> None:
    events: list[object] = []

    async def on_cancelled(event: ExecutionCancelled) -> None:
        events.append(event)

    services["bus"].subscribe(ExecutionCancelled, on_cancelled)

    long_suite = services["project"].path / "tests" / "long.robot"
    long_suite.write_text(
        "*** Test Cases ***\nLong\n    Sleep    30s\n",
        encoding="utf-8",
    )

    run = await services["execution_service"].run_file(str(long_suite))
    assert run.status == ExecutionStatus.RUNNING
    await asyncio.sleep(0.5)
    stopped = await services["execution_service"].stop()
    assert stopped is not None
    await _wait_until_done(services["execution_service"], timeout=15)
    final = await services["execution_service"].get_status()
    assert final is not None
    assert final.status == ExecutionStatus.CANCELLED
    assert any(isinstance(e, ExecutionCancelled) for e in events)


@pytest.mark.asyncio
async def test_history_persistence(services) -> None:
    await services["execution_service"].run_file(str(services["suite"]))
    await _wait_until_done(services["execution_service"])

    history = await services["execution_service"].list_history()
    assert len(history) >= 1
    assert history[0].project_name == "Demo"
    assert history[0].output_xml is not None

    loaded = await services["exec_repo"].get(history[0].id)
    assert loaded is not None
    assert loaded.status == ExecutionStatus.FINISHED


@pytest.mark.asyncio
async def test_rejects_missing_robot_before_creating_run(services) -> None:
    """QA-001: never create a fake run when Robot Framework is missing."""
    env = services["context"].environment
    assert env is not None
    # Simulate an environment metadata without Robot (and block import probe).
    env.robot_version = None
    env.robot_executable = None
    original_python = env.python_executable
    env.python_executable = str(services["tmp_path"] / "missing-python")

    before = await services["exec_repo"].list_by_workspace(
        services["context"].workspace.id,
        limit=50,
    )
    with pytest.raises(ExecutionValidationError, match="Robot Framework|environment") as exc:
        await services["execution_service"].run_file(str(services["suite"]))
    assert getattr(exc.value, "code", None) in {"robot_missing", "environment_missing"}

    after = await services["exec_repo"].list_by_workspace(
        services["context"].workspace.id,
        limit=50,
    )
    assert len(after) == len(before)

    env.python_executable = original_python


@pytest.mark.asyncio
async def test_stop_is_idempotent_when_idle(services) -> None:
    stopped = await services["execution_service"].stop()
    assert stopped is None


@pytest.mark.asyncio
async def test_requires_active_session(tmp_path: Path) -> None:
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    db = tmp_path / "t.db"
    repo = SqliteExecutionRepository(db)
    await repo.initialize()
    service = ExecutionService(
        context=context,
        event_bus=bus,
        runner=SubprocessRunner(),
        results_store=FilesystemResultsStore(),
        repository=repo,
    )
    with pytest.raises(ExecutionValidationError, match="workspace"):
        await service.run_project()


@pytest.mark.skipif(sys.platform == "win32", reason="venv python is a symlink on Unix")
@pytest.mark.asyncio
async def test_runner_invokes_venv_wrapper_not_system_python(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    wrapper = bin_dir / "python"
    wrapper.symlink_to(sys.executable)
    (tmp_path / "pyvenv.cfg").write_text("home = /\n", encoding="utf-8")
    suite = tmp_path / "suite.robot"
    suite.write_text("*** Test Cases ***\nX\n    No Operation\n", encoding="utf-8")
    output_dir = tmp_path / "out"

    captured: dict[str, object] = {}

    class _FakeProcess:
        def __init__(self) -> None:
            self.pid = 4242
            self.stdout = None
            self.stderr = None
            self.returncode = 0

        async def wait(self) -> int:
            return 0

    async def fake_exec(*command: str, **kwargs: object) -> _FakeProcess:
        captured["command"] = command
        captured["env"] = kwargs.get("env")
        return _FakeProcess()

    monkeypatch.setattr(
        "robot_studio.infrastructure.execution.subprocess_runner.asyncio.create_subprocess_exec",
        fake_exec,
    )

    runner = SubprocessRunner()
    started = await runner.start(
        {
            "python_executable": str(wrapper),
            "suite": str(suite),
            "output_dir": str(output_dir),
            "cwd": str(tmp_path),
        },
    )
    command = captured["command"]
    assert isinstance(command, tuple)
    assert command[0] == str(wrapper.absolute())
    assert command[0] != str(Path(sys.executable).resolve())
    assert started["status"] == ExecutionStatus.RUNNING.value
    run_id = UUID(str(started["run_id"]))
    await runner.wait(run_id)
    runner.release(run_id)


@pytest.mark.asyncio
async def test_broadcast_preserves_finished_under_output_backpressure() -> None:
    """Control events must survive a full subscriber queue of output lines."""
    from robot_studio.application.services.execution_service import (
        _CONTROL_EVENT_TYPES,
        _enqueue_preserving_control,
    )

    queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=8)
    for index in range(8):
        queue.put_nowait({"type": "output", "line": f"line-{index}"})

    finished = {"type": "finished", "run_id": "run-1", "status": "finished"}
    assert "finished" in _CONTROL_EVENT_TYPES
    _enqueue_preserving_control(queue, finished)

    items: list[dict] = []
    while not queue.empty():
        items.append(queue.get_nowait())
    assert any(item.get("type") == "finished" for item in items)
    assert items[-1]["type"] == "finished"
    assert sum(1 for item in items if item.get("type") == "output") < 8
