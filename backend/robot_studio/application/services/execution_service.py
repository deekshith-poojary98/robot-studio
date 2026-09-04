"""Robot Framework execution use cases."""

from __future__ import annotations

import asyncio
import logging
import shutil
import subprocess
from collections import deque
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

logger = logging.getLogger(__name__)

from robot_studio.application.services.execution_plan import (
    ExecutionPlan,
    ExecutionPlanError,
    plan_to_robot_args,
    resolve_variable_files,
)
from robot_studio.application.services.run_configuration_service import (
    RunConfigurationService,
    RunConfigurationValidationError,
)
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import (
    EventBus,
    ExecutionCancelled,
    ExecutionFailed,
    ExecutionFinished,
    ExecutionOutput,
    ExecutionStarted,
)
from robot_studio.domain.interfaces.runner import ResultsStore, Runner
from robot_studio.domain.models import Environment, ExecutionRun, ExecutionStatus
from robot_studio.infrastructure.environment.python_provider import (
    _host_python_subprocess_env,
)
from robot_studio.infrastructure.execution.output_stats import (
    load_or_build_file_outcomes,
)
from robot_studio.infrastructure.execution.parent_suite_target import (
    expand_parent_suite_target,
)
from robot_studio.infrastructure.execution.subprocess_runner import (
    RunnerError,
    SubprocessRunner,
)
from robot_studio.infrastructure.process_utils import windows_no_window_kwargs
from robot_studio.infrastructure.repositories.environment_repository import (
    SqliteEnvironmentRepository,
)
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
)
from robot_studio.infrastructure.workspace.filesystem import studio_reports_root

#: Lines of console output kept so a failed run can explain itself.
_OUTPUT_TAIL_LINES = 40

#: Robot Framework itself could not be imported — the environment is broken.
_ROBOT_MISSING_MARKERS = (
    "no module named robot",
    "no module named 'robot'",
)

#: Stream events that must not be discarded under output backpressure.
_CONTROL_EVENT_TYPES = frozenset(
    {
        "status",
        "started",
        "finished",
        "failed",
        "cancelled",
        "aborted",
    },
)


def _enqueue_preserving_control(queue: asyncio.Queue[dict], message: dict) -> None:
    """Enqueue [message] when full by dropping oldest *output* frames first.

    Large runs flood the subscriber queue with stdout. The previous
    drop-oldest strategy could discard ``finished`` / ``failed`` while Live
    Output still showed Robot's summary — leaving the UI stuck on Running.
    """
    buffered: list[dict] = []
    while True:
        try:
            buffered.append(queue.get_nowait())
        except asyncio.QueueEmpty:
            break

    controls = [item for item in buffered if item.get("type") in _CONTROL_EVENT_TYPES]
    outputs = [item for item in buffered if item.get("type") not in _CONTROL_EVENT_TYPES]
    maxsize = queue.maxsize if queue.maxsize > 0 else len(buffered) + 1
    room_for_outputs = max(0, maxsize - len(controls) - 1)
    kept = controls + outputs[-room_for_outputs:]
    kept.append(message)
    for item in kept[:maxsize]:
        queue.put_nowait(item)


def _probe_robot_version(python: Path) -> subprocess.CompletedProcess[str]:
    """Import-check Robot off the asyncio thread (Windows CreateProcess safety)."""
    return subprocess.run(
        [
            str(python),
            "-c",
            "import robot; print(getattr(robot, '__version__', 'ok'))",
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
        env=_host_python_subprocess_env(),
        **windows_no_window_kwargs(),
    )


def robot_is_missing(output: list[str]) -> bool:
    """True when the console says Robot Framework could not be imported.

    Distinguishes a broken environment (discard the run) from Robot running and
    rejecting the request (keep the run and report what Robot said).
    """
    for line in output:
        folded = line.casefold()
        if any(marker in folded for marker in _ROBOT_MISSING_MARKERS):
            return True
    return False


def first_robot_error(output: list[str]) -> str:
    """Robot's own first ``[ ERROR ]`` line, e.g. a bad option or no matches."""
    for line in output:
        stripped = line.strip()
        if stripped.startswith("[ ERROR ]"):
            return stripped.removeprefix("[ ERROR ]").strip()
    return ""


class ExecutionValidationError(Exception):
    """Raised when an execution cannot start or be controlled."""

    def __init__(self, message: str, *, code: str | None = None) -> None:
        super().__init__(message)
        self.code = code


@dataclass
class _Subscriber:
    queue: asyncio.Queue[dict]


@dataclass
class ExecutionService:
    context: WorkspaceContext
    event_bus: EventBus
    runner: Runner
    results_store: ResultsStore
    repository: SqliteExecutionRepository
    environment_repository: SqliteEnvironmentRepository | None = None
    run_configuration_service: RunConfigurationService | None = None
    _current: ExecutionRun | None = field(default=None, init=False)
    _monitor_task: asyncio.Task | None = field(default=None, init=False)
    _subscribers: list[_Subscriber] = field(default_factory=list, init=False)
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    def _require_session(self):
        workspace, project = self._require_workspace_project()
        environment = self.context.environment
        if environment is None:
            raise ExecutionValidationError(
                "Activate a Python environment before running tests",
                code="environment_required",
            )
        return workspace, project, environment

    def _require_workspace_project(self):
        workspace = self.context.workspace
        if workspace is None:
            raise ExecutionValidationError("Open a workspace before running tests")
        project = self.context.project
        if project is None:
            raise ExecutionValidationError("Open a project before running tests")
        return workspace, project

    async def _load_pinned_environment(
        self,
        environment_id: UUID,
        workspace_id: UUID,
    ) -> Environment:
        repo = self.environment_repository
        if repo is None:
            raise ExecutionValidationError(
                "Environments are unavailable",
                code="environment_missing",
            )
        environment = await repo.get(environment_id)
        if environment is None or environment.workspace_id != workspace_id:
            raise ExecutionValidationError(
                "This run configuration's environment is missing. "
                "Edit the configuration to pick another environment.",
                code="environment_missing",
            )
        if not Path(environment.python_executable).is_file():
            raise ExecutionValidationError(
                f'The configuration environment "{environment.name}" is missing on disk. '
                "Edit the configuration to pick another environment.",
                code="environment_missing",
            )
        return environment

    async def _plan_for_run(
        self,
        *,
        suite: str,
        target_robot_args: list[str] | None = None,
        run_label: str | None = None,
        configuration_id: UUID | None = None,
    ) -> ExecutionPlan:
        workspace, project = self._require_workspace_project()
        config = None
        if configuration_id is not None:
            service = self.run_configuration_service
            if service is None:
                raise ExecutionValidationError("Run configurations are unavailable")
            try:
                config = service.get(configuration_id)
            except RunConfigurationValidationError as exc:
                raise ExecutionValidationError(
                    str(exc),
                    code=exc.code or "configuration_missing",
                ) from exc

        environment = self.context.environment
        if config is not None and config.environment_id is not None:
            environment = await self._load_pinned_environment(
                config.environment_id,
                workspace.id,
            )
        if environment is None:
            raise ExecutionValidationError(
                "Activate a Python environment before running tests",
                code="environment_required",
            )

        try:
            variable_files = resolve_variable_files(
                project.path,
                list(config.variable_files) if config else [],
            )
            return ExecutionPlan(
                suite=suite,
                environment=environment,
                include_tags=list(config.include_tags) if config else [],
                exclude_tags=list(config.exclude_tags) if config else [],
                variables=list(config.variables) if config else [],
                variable_files=variable_files,
                extra_robot_args=list(config.extra_robot_args) if config else [],
                target_robot_args=list(target_robot_args or []),
                configuration_id=config.id if config else None,
                configuration_name=config.name if config else None,
                run_label=run_label,
            )
        except ExecutionPlanError as exc:
            raise ExecutionValidationError(str(exc), code=exc.code) from exc

    async def _assert_robot_ready(self, environment) -> None:
        """Block execution before any run row is created when Robot is missing."""
        if environment.robot_version or environment.robot_executable:
            return
        python = Path(environment.python_executable)
        if not python.is_file():
            raise ExecutionValidationError(
                "The active environment's Python executable is missing on disk. "
                "Recreate or select another environment.",
                code="environment_missing",
            )
        try:
            result = await asyncio.to_thread(
                _probe_robot_version,
                python,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ExecutionValidationError(
                "Could not verify Robot Framework in the active environment.",
                code="robot_missing",
            ) from exc
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            raise ExecutionValidationError(
                "Robot Framework is not installed in the active environment. "
                "Install Robot Framework before running tests."
                + (f" ({detail})" if detail else ""),
                code="robot_missing",
            )

    async def run_file(
        self,
        file_path: str | None = None,
        *,
        configuration_id: UUID | None = None,
    ) -> ExecutionRun:
        workspace, project = self._require_workspace_project()
        suite = self._resolve_suite(project.path, file_path)
        expanded = expand_parent_suite_target(Path(suite), project.path)
        plan = await self._plan_for_run(
            suite=str(expanded.data_source),
            target_robot_args=list(expanded.filter_args),
            configuration_id=configuration_id,
        )
        await self._assert_robot_ready(plan.environment)
        return await self._start_run(
            workspace_id=workspace.id,
            project_id=project.id,
            project_name=project.name,
            project_path=project.path,
            environment_id=plan.environment.id,
            environment_name=plan.environment.name,
            python_executable=plan.environment.python_executable,
            suite=str(expanded.data_source),
            workspace_path=workspace.path,
            robot_args=plan_to_robot_args(plan),
            run_label=suite,
            configuration_id=plan.configuration_id,
            configuration_name=plan.configuration_name,
        )

    async def run_project(self, *, configuration_id: UUID | None = None) -> ExecutionRun:
        workspace, project = self._require_workspace_project()
        suites = list(project.path.rglob("*.robot"))
        if not suites:
            raise ExecutionValidationError(
                f"No .robot files found in project '{project.name}'",
            )
        label = f"Project: {project.name}"
        plan = await self._plan_for_run(
            suite=str(project.path),
            run_label=label,
            configuration_id=configuration_id,
        )
        await self._assert_robot_ready(plan.environment)
        return await self._start_run(
            workspace_id=workspace.id,
            project_id=project.id,
            project_name=project.name,
            project_path=project.path,
            environment_id=plan.environment.id,
            environment_name=plan.environment.name,
            python_executable=plan.environment.python_executable,
            suite=str(project.path),
            workspace_path=workspace.path,
            robot_args=plan_to_robot_args(plan),
            run_label=label,
            configuration_id=plan.configuration_id,
            configuration_name=plan.configuration_name,
        )

    async def run_with_options(
        self,
        *,
        suite: str,
        robot_args: list[str] | None = None,
        run_label: str | None = None,
        project_path: Path | None = None,
        configuration_id: UUID | None = None,
    ) -> ExecutionRun:
        """Start a Robot run with extra CLI args (e.g. --test / --include)."""
        workspace, project = self._require_workspace_project()
        resolved_suite = suite
        if not Path(suite).is_absolute():
            candidate = (project.path / suite).resolve()
            if candidate.exists():
                resolved_suite = str(candidate)
        expanded = expand_parent_suite_target(Path(resolved_suite), project.path)
        plan = await self._plan_for_run(
            suite=str(expanded.data_source),
            target_robot_args=[*expanded.filter_args, *(robot_args or [])],
            run_label=run_label,
            configuration_id=configuration_id,
        )
        await self._assert_robot_ready(plan.environment)
        return await self._start_run(
            workspace_id=workspace.id,
            project_id=project.id,
            project_name=project.name,
            project_path=project_path or project.path,
            environment_id=plan.environment.id,
            environment_name=plan.environment.name,
            python_executable=plan.environment.python_executable,
            suite=str(expanded.data_source),
            workspace_path=workspace.path,
            robot_args=plan_to_robot_args(plan),
            run_label=run_label,
            configuration_id=plan.configuration_id,
            configuration_name=plan.configuration_name,
        )

    async def stop(self) -> ExecutionRun | None:
        async with self._lock:
            current = self._current
        if current is None or current.status not in {
            ExecutionStatus.STARTING,
            ExecutionStatus.RUNNING,
            ExecutionStatus.STOPPING,
        }:
            return current

        updated = current.model_copy(update={"status": ExecutionStatus.STOPPING})
        async with self._lock:
            self._current = updated
        await self.repository.update(updated)
        await self._broadcast(
            {"type": "status", "run_id": str(updated.id), "status": updated.status.value},
        )

        logger.info("Stopping run %s", updated.id)
        try:
            await self.runner.stop(updated.id)
        except RunnerError as exc:
            logger.warning(
                "Stop failed for run %s: %s",
                updated.id,
                exc,
            )
            raise ExecutionValidationError(str(exc)) from exc

        await self.event_bus.publish(ExecutionCancelled(run_id=updated.id))
        return await self.get_status()

    async def get_status(self) -> ExecutionRun | None:
        async with self._lock:
            return self._current

    async def list_history(self, *, limit: int = 50) -> list[ExecutionRun]:
        workspace = self.context.workspace
        if workspace is None:
            raise ExecutionValidationError("Open a workspace to view execution history")
        runs = await self.repository.list_by_workspace(workspace.id, limit=limit * 2)
        real = [r for r in runs if r.status != ExecutionStatus.ABORTED]
        return real[:limit]

    async def subscribe(self) -> asyncio.Queue[dict]:
        queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=500)
        self._subscribers.append(_Subscriber(queue=queue))
        async with self._lock:
            if self._current is not None:
                await queue.put(
                    {
                        "type": "status",
                        "run_id": str(self._current.id),
                        "status": self._current.status.value,
                    },
                )
        return queue

    async def unsubscribe(self, queue: asyncio.Queue[dict]) -> None:
        self._subscribers = [item for item in self._subscribers if item.queue is not queue]

    async def _discard_aborted_run(
        self,
        run: ExecutionRun,
        *,
        message: str,
    ) -> None:
        """Remove a run that never actually started Robot Framework."""
        await self.repository.delete(run.id)
        if run.output_dir is not None:
            shutil.rmtree(run.output_dir, ignore_errors=True)
        async with self._lock:
            if self._current is not None and self._current.id == run.id:
                self._current = None
        logger.warning("Aborted run %s: %s", run.id, message)
        await self._broadcast(
            {
                "type": "aborted",
                "run_id": str(run.id),
                "status": ExecutionStatus.ABORTED.value,
                "message": message,
            },
        )

    async def _start_run(
        self,
        *,
        workspace_id: UUID,
        project_id: UUID,
        project_name: str,
        project_path: Path,
        environment_id: UUID,
        environment_name: str,
        python_executable: Path,
        suite: str,
        workspace_path: Path,
        robot_args: list[str] | None = None,
        run_label: str | None = None,
        configuration_id: UUID | None = None,
        configuration_name: str | None = None,
    ) -> ExecutionRun:
        async with self._lock:
            if self._current is not None and self._current.status in {
                ExecutionStatus.STARTING,
                ExecutionStatus.RUNNING,
                ExecutionStatus.STOPPING,
            }:
                raise ExecutionValidationError(
                    "An execution is already in progress. Stop it before starting another.",
                )

        run_id = uuid4()
        stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S-%f")
        output_dir = studio_reports_root(workspace_path) / f"Run-{stamp}"
        output_dir.mkdir(parents=True, exist_ok=True)

        display_suite = run_label or suite
        run = ExecutionRun(
            id=run_id,
            workspace_id=workspace_id,
            project_id=project_id,
            environment_id=environment_id,
            project_name=project_name,
            suite=display_suite,
            status=ExecutionStatus.STARTING,
            started_at=datetime.now(UTC),
            command="",
            output_dir=output_dir,
            environment_name=environment_name,
            configuration_id=configuration_id,
            configuration_name=configuration_name or "",
        )
        await self.repository.create(run)
        async with self._lock:
            self._current = run

        await self.event_bus.publish(
            ExecutionStarted(
                run_id=run_id,
                project_id=project_id,
                workspace_id=workspace_id,
            ),
        )
        await self._broadcast(
            {
                "type": "started",
                "run_id": str(run_id),
                "status": ExecutionStatus.STARTING.value,
                "suite": display_suite,
            },
        )

        try:
            started = await self.runner.start(
                {
                    "run_id": str(run_id),
                    "python_executable": str(python_executable),
                    "suite": suite,
                    "output_dir": str(output_dir),
                    "cwd": str(project_path),
                    "robot_args": list(robot_args or []),
                },
            )
        except RunnerError as exc:
            await self._discard_aborted_run(run, message=str(exc))
            raise ExecutionValidationError(str(exc), code="start_failed") from exc

        running = run.model_copy(
            update={
                "status": ExecutionStatus.RUNNING,
                "command": str(started.get("command") or ""),
            },
        )
        await self.repository.update(running)
        async with self._lock:
            self._current = running

        logger.info(
            "Started run %s suite=%s env=%s config=%s",
            run_id,
            display_suite,
            environment_name,
            configuration_name or "-",
        )

        await self._broadcast(
            {
                "type": "status",
                "run_id": str(run_id),
                "status": ExecutionStatus.RUNNING.value,
                "command": running.command,
            },
        )

        self._monitor_task = asyncio.create_task(self._monitor(running))
        return running

    async def _monitor(self, run: ExecutionRun) -> None:
        try:
            tail: deque[str] = deque(maxlen=_OUTPUT_TAIL_LINES)
            async for line in self.runner.stream_output(run.id):
                tail.append(line)
                await self.event_bus.publish(
                    ExecutionOutput(run_id=run.id, line=line),
                )
                await self._broadcast(
                    {
                        "type": "output",
                        "run_id": str(run.id),
                        "line": line,
                    },
                )

            exit_code: int | None = None
            status = ExecutionStatus.FAILED
            if isinstance(self.runner, SubprocessRunner):
                exit_code = await self.runner.wait(run.id)
                status = self.runner.get_status(run.id) or ExecutionStatus.FAILED
                self.runner.release(run.id)
            else:
                exit_code = 0
                status = ExecutionStatus.FINISHED

            finished_at = datetime.now(UTC)
            duration_ms = int((finished_at - run.started_at).total_seconds() * 1000)
            artifacts = await self.results_store.ingest(run.id, run.output_dir or Path("."))

            has_xml = bool(artifacts.get("output_xml"))
            console = list(tail)
            failure_message = ""
            if (
                status == ExecutionStatus.FAILED
                and not has_xml
                and duration_ms < 3000
                and (exit_code not in (None, 0))
            ):
                # Only a broken environment justifies deleting the run. Robot
                # exiting fast with a real complaint (bad option, no matching
                # tests, invalid data) must stay visible with its own message,
                # otherwise the run vanishes and we blame the wrong thing.
                if robot_is_missing(console) or not console:
                    await self._discard_aborted_run(
                        run,
                        message=(
                            "Robot Framework did not produce results. "
                            "Confirm Robot Framework is installed in the active environment."
                        ),
                    )
                    return
                failure_message = first_robot_error(console)

            final = run.model_copy(
                update={
                    "status": status,
                    "finished_at": finished_at,
                    "duration_ms": duration_ms,
                    "exit_code": exit_code,
                    "output_dir": Path(artifacts["output_dir"])
                    if artifacts.get("output_dir")
                    else run.output_dir,
                    "output_xml": Path(artifacts["output_xml"])
                    if artifacts.get("output_xml")
                    else None,
                    "log_html": Path(artifacts["log_html"])
                    if artifacts.get("log_html")
                    else None,
                    "report_html": Path(artifacts["report_html"])
                    if artifacts.get("report_html")
                    else None,
                    "robot_version": artifacts.get("robot_version"),
                    "total_tests": artifacts.get("total_tests"),
                    "passed": artifacts.get("passed"),
                    "failed": artifacts.get("failed"),
                    "skipped": artifacts.get("skipped"),
                },
            )
            await self.repository.update(final)
            async with self._lock:
                self._current = final

            # Tell the UI the run is done *before* domain handlers (report
            # indexing, Test Explorer XML parse, execution linking). Those can
            # take tens of seconds on million-test output.xml and previously
            # held the Running timer / Stop button hostage.
            if status == ExecutionStatus.CANCELLED:
                logger.info(
                    "Run %s cancelled after %dms exit=%s",
                    run.id,
                    duration_ms,
                    exit_code,
                )
                await self._broadcast(
                    {
                        "type": "cancelled",
                        "run_id": str(run.id),
                        "status": status.value,
                        "exit_code": exit_code,
                    },
                )
                await self.event_bus.publish(ExecutionCancelled(run_id=run.id))
            elif status == ExecutionStatus.FAILED:
                logger.warning(
                    "Run %s failed after %dms exit=%s message=%s",
                    run.id,
                    duration_ms,
                    exit_code,
                    failure_message or "-",
                )
                await self._broadcast(
                    {
                        "type": "failed",
                        "run_id": str(run.id),
                        "status": status.value,
                        "exit_code": exit_code,
                        "message": failure_message,
                    },
                )
                await self.event_bus.publish(
                    ExecutionFailed(
                        run_id=run.id,
                        message=failure_message or f"Exit code {exit_code}",
                    ),
                )
                await self.event_bus.publish(
                    ExecutionFinished(
                        run_id=run.id,
                        status=status.value,
                        exit_code=exit_code,
                    ),
                )
            else:
                logger.info(
                    "Run %s finished after %dms exit=%s passed=%s failed=%s",
                    run.id,
                    duration_ms,
                    exit_code,
                    final.passed,
                    final.failed,
                )
                await self._broadcast(
                    {
                        "type": "finished",
                        "run_id": str(run.id),
                        "status": status.value,
                        "exit_code": exit_code,
                    },
                )
                await self.event_bus.publish(
                    ExecutionFinished(
                        run_id=run.id,
                        status=status.value,
                        exit_code=exit_code,
                    ),
                )

            # Insights file fan-out — never block the finish path.
            if final.output_dir is not None:
                asyncio.create_task(
                    self._warm_file_outcomes(final.output_dir),
                    name=f"file-outcomes-{run.id}",
                )
        except Exception as exc:
            logger.exception("Run %s monitor crashed", run.id)
            failed = run.model_copy(
                update={
                    "status": ExecutionStatus.FAILED,
                    "finished_at": datetime.now(UTC),
                    "exit_code": -1,
                },
            )
            await self.repository.update(failed)
            async with self._lock:
                self._current = failed
            await self._broadcast(
                {
                    "type": "failed",
                    "run_id": str(run.id),
                    "status": ExecutionStatus.FAILED.value,
                    "message": str(exc),
                },
            )
            await self.event_bus.publish(
                ExecutionFailed(run_id=run.id, message=str(exc)),
            )

    async def _warm_file_outcomes(self, output_dir: Path) -> None:
        """Build Insights ``file_outcomes.json`` off the finish critical path."""
        try:
            await asyncio.to_thread(load_or_build_file_outcomes, output_dir)
        except Exception:
            logger.debug(
                "file_outcomes warm failed for %s",
                output_dir,
                exc_info=True,
            )
            return

    async def _broadcast(self, message: dict) -> None:
        stale: list[_Subscriber] = []
        message_type = message.get("type")
        is_control = message_type in _CONTROL_EVENT_TYPES
        for subscriber in list(self._subscribers):
            try:
                subscriber.queue.put_nowait(message)
            except asyncio.QueueFull:
                try:
                    if is_control:
                        _enqueue_preserving_control(subscriber.queue, message)
                    else:
                        _ = subscriber.queue.get_nowait()
                        subscriber.queue.put_nowait(message)
                except Exception:  # noqa: BLE001
                    stale.append(subscriber)
        if stale:
            self._subscribers = [item for item in self._subscribers if item not in stale]

    @staticmethod
    def _resolve_suite(project_path: Path, file_path: str | None) -> str:
        project_root = project_path.resolve()
        if file_path:
            candidate = Path(file_path).expanduser()
            if not candidate.is_absolute():
                candidate = (project_root / candidate).resolve()
            else:
                candidate = candidate.resolve()
            try:
                candidate.relative_to(project_root)
            except ValueError as exc:
                raise ExecutionValidationError(
                    f"Robot file must be inside the active project: '{candidate}'",
                ) from exc
            if not candidate.is_file() or candidate.suffix != ".robot":
                raise ExecutionValidationError(
                    f"Robot file not found: '{candidate}'",
                )
            return str(candidate)

        discovered = sorted(project_path.rglob("*.robot"))
        if not discovered:
            raise ExecutionValidationError(
                f"No .robot files found in project '{project_path.name}'",
            )
        return str(discovered[0].resolve())
