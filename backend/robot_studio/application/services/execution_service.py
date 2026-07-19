"""Robot Framework execution use cases."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

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
from robot_studio.domain.models import ExecutionRun, ExecutionStatus
from robot_studio.infrastructure.execution.subprocess_runner import (
    RunnerError,
    SubprocessRunner,
)
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
)


class ExecutionValidationError(Exception):
    """Raised when an execution cannot start or be controlled."""


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
    _current: ExecutionRun | None = field(default=None, init=False)
    _monitor_task: asyncio.Task | None = field(default=None, init=False)
    _subscribers: list[_Subscriber] = field(default_factory=list, init=False)
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    def _require_session(self):
        workspace = self.context.workspace
        if workspace is None:
            raise ExecutionValidationError("Open a workspace before running tests")
        project = self.context.project
        if project is None:
            raise ExecutionValidationError("Open a project before running tests")
        environment = self.context.environment
        if environment is None:
            raise ExecutionValidationError(
                "Activate a Python environment before running tests",
            )
        return workspace, project, environment

    async def run_file(self, file_path: str | None = None) -> ExecutionRun:
        workspace, project, environment = self._require_session()
        suite = self._resolve_suite(project.path, file_path)
        return await self._start_run(
            workspace_id=workspace.id,
            project_id=project.id,
            project_name=project.name,
            project_path=project.path,
            environment_id=environment.id,
            environment_name=environment.name,
            python_executable=environment.python_executable,
            suite=suite,
            workspace_path=workspace.path,
        )

    async def run_project(self) -> ExecutionRun:
        workspace, project, environment = self._require_session()
        suites = list(project.path.rglob("*.robot"))
        if not suites:
            raise ExecutionValidationError(
                f"No .robot files found in project '{project.name}'",
            )
        return await self._start_run(
            workspace_id=workspace.id,
            project_id=project.id,
            project_name=project.name,
            project_path=project.path,
            environment_id=environment.id,
            environment_name=environment.name,
            python_executable=environment.python_executable,
            suite=str(project.path),
            workspace_path=workspace.path,
        )

    async def stop(self) -> ExecutionRun | None:
        async with self._lock:
            current = self._current
        if current is None or current.status not in {
            ExecutionStatus.STARTING,
            ExecutionStatus.RUNNING,
            ExecutionStatus.STOPPING,
        }:
            raise ExecutionValidationError("No running execution to stop")

        updated = current.model_copy(update={"status": ExecutionStatus.STOPPING})
        async with self._lock:
            self._current = updated
        await self.repository.update(updated)
        await self._broadcast(
            {"type": "status", "run_id": str(updated.id), "status": updated.status.value},
        )

        try:
            await self.runner.stop(updated.id)
        except RunnerError as exc:
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
        return await self.repository.list_by_workspace(workspace.id, limit=limit)

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
        stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
        output_dir = workspace_path / "Reports" / f"Run-{stamp}"
        output_dir.mkdir(parents=True, exist_ok=True)

        run = ExecutionRun(
            id=run_id,
            workspace_id=workspace_id,
            project_id=project_id,
            environment_id=environment_id,
            project_name=project_name,
            suite=suite,
            status=ExecutionStatus.STARTING,
            started_at=datetime.now(UTC),
            command="",
            output_dir=output_dir,
            environment_name=environment_name,
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
                "suite": suite,
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
                },
            )
        except RunnerError as exc:
            failed = run.model_copy(
                update={
                    "status": ExecutionStatus.FAILED,
                    "finished_at": datetime.now(UTC),
                    "duration_ms": 0,
                    "exit_code": -1,
                },
            )
            await self.repository.update(failed)
            async with self._lock:
                self._current = failed
            await self.event_bus.publish(
                ExecutionFailed(run_id=run_id, message=str(exc)),
            )
            await self._broadcast(
                {
                    "type": "failed",
                    "run_id": str(run_id),
                    "status": ExecutionStatus.FAILED.value,
                    "message": str(exc),
                },
            )
            raise ExecutionValidationError(str(exc)) from exc

        running = run.model_copy(
            update={
                "status": ExecutionStatus.RUNNING,
                "command": str(started.get("command") or ""),
            },
        )
        await self.repository.update(running)
        async with self._lock:
            self._current = running

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
            async for line in self.runner.stream_output(run.id):
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
            else:
                exit_code = 0
                status = ExecutionStatus.FINISHED

            finished_at = datetime.now(UTC)
            duration_ms = int((finished_at - run.started_at).total_seconds() * 1000)
            artifacts = await self.results_store.ingest(run.id, run.output_dir or Path("."))

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

            if status == ExecutionStatus.CANCELLED:
                await self.event_bus.publish(ExecutionCancelled(run_id=run.id))
                await self._broadcast(
                    {
                        "type": "cancelled",
                        "run_id": str(run.id),
                        "status": status.value,
                        "exit_code": exit_code,
                    },
                )
            elif status == ExecutionStatus.FAILED:
                await self.event_bus.publish(
                    ExecutionFailed(run_id=run.id, message=f"Exit code {exit_code}"),
                )
                await self.event_bus.publish(
                    ExecutionFinished(
                        run_id=run.id,
                        status=status.value,
                        exit_code=exit_code,
                    ),
                )
                await self._broadcast(
                    {
                        "type": "failed",
                        "run_id": str(run.id),
                        "status": status.value,
                        "exit_code": exit_code,
                    },
                )
            else:
                await self.event_bus.publish(
                    ExecutionFinished(
                        run_id=run.id,
                        status=status.value,
                        exit_code=exit_code,
                    ),
                )
                await self._broadcast(
                    {
                        "type": "finished",
                        "run_id": str(run.id),
                        "status": status.value,
                        "exit_code": exit_code,
                    },
                )
        except Exception as exc:  # noqa: BLE001 — surface unexpected monitor failures
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
            await self.event_bus.publish(
                ExecutionFailed(run_id=run.id, message=str(exc)),
            )
            await self._broadcast(
                {
                    "type": "failed",
                    "run_id": str(run.id),
                    "status": ExecutionStatus.FAILED.value,
                    "message": str(exc),
                },
            )

    async def _broadcast(self, message: dict) -> None:
        stale: list[_Subscriber] = []
        for subscriber in list(self._subscribers):
            try:
                subscriber.queue.put_nowait(message)
            except asyncio.QueueFull:
                try:
                    _ = subscriber.queue.get_nowait()
                    subscriber.queue.put_nowait(message)
                except Exception:  # noqa: BLE001
                    stale.append(subscriber)
        if stale:
            self._subscribers = [item for item in self._subscribers if item not in stale]

    @staticmethod
    def _resolve_suite(project_path: Path, file_path: str | None) -> str:
        if file_path:
            candidate = Path(file_path).expanduser()
            if not candidate.is_absolute():
                candidate = (project_path / candidate).resolve()
            else:
                candidate = candidate.resolve()
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
