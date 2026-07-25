"""Report and run-index use cases built on ExecutionRepository + ResultsStore."""

from __future__ import annotations

import os
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import (
    EventBus,
    ExecutionCancelled,
    ExecutionFailed,
    ExecutionFinished,
    RunDeleted,
    RunIndexed,
)
from robot_studio.domain.interfaces.runner import ResultsStore
from robot_studio.domain.models import DashboardSummary, ExecutionRun
from robot_studio.infrastructure.execution.results_store import FilesystemResultsStore
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
)


class ReportValidationError(Exception):
    """Raised when a report operation cannot proceed."""


@dataclass
class ReportService:
    context: WorkspaceContext
    event_bus: EventBus
    results_store: ResultsStore
    repository: SqliteExecutionRepository
    _subscribed: bool = field(default=False, init=False)

    def start(self) -> None:
        if self._subscribed:
            return
        self.event_bus.subscribe(ExecutionFinished, self._on_execution_finished)
        self.event_bus.subscribe(ExecutionFailed, self._on_execution_failed)
        self.event_bus.subscribe(ExecutionCancelled, self._on_execution_cancelled)
        self._subscribed = True

    async def _on_execution_finished(self, event: ExecutionFinished) -> None:
        await self.index_run(event.run_id)

    async def _on_execution_failed(self, event: ExecutionFailed) -> None:
        await self.index_run(event.run_id)

    async def _on_execution_cancelled(self, event: ExecutionCancelled) -> None:
        await self.index_run(event.run_id)

    async def index_run(self, run_id: UUID) -> ExecutionRun | None:
        run = await self.repository.get(run_id)
        if run is None:
            return None
        output_dir = run.output_dir or Path(".")
        artifacts = await self.results_store.discover_run(run_id, output_dir)
        if isinstance(self.results_store, FilesystemResultsStore):
            indexed = self.results_store.apply_to_run(run, artifacts)
        else:
            indexed = run.model_copy(
                update={
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
        await self.repository.update(indexed)
        await self.event_bus.publish(
            RunIndexed(run_id=indexed.id, workspace_id=indexed.workspace_id),
        )
        return indexed

    def _require_workspace(self):
        workspace = self.context.workspace
        if workspace is None:
            raise ReportValidationError("Open a workspace to view reports")
        return workspace

    async def list_runs(self, *, limit: int = 50) -> list[ExecutionRun]:
        workspace = self._require_workspace()
        return await self.repository.list_by_workspace(workspace.id, limit=limit)

    async def get_run(self, run_id: UUID) -> ExecutionRun:
        self._require_workspace()
        run = await self.repository.get(run_id)
        if run is None:
            raise ReportValidationError(f"Run not found: {run_id}")
        # Refresh stats if artifacts exist but stats were never indexed.
        if run.total_tests is None and run.output_dir is not None:
            refreshed = await self.index_run(run_id)
            if refreshed is not None:
                return refreshed
        return run

    async def delete_run(self, run_id: UUID) -> None:
        workspace = self._require_workspace()
        run = await self.repository.get(run_id)
        if run is None:
            raise ReportValidationError(f"Run not found: {run_id}")
        if run.workspace_id != workspace.id:
            raise ReportValidationError("Run does not belong to the active workspace")
        await self.results_store.delete_run(run_id, run.output_dir)
        await self.repository.delete(run_id)
        await self.event_bus.publish(
            RunDeleted(run_id=run_id, workspace_id=workspace.id),
        )

    async def open_log(self, run_id: UUID) -> Path:
        run = await self.get_run(run_id)
        path = run.log_html
        if path is None or not Path(path).is_file():
            raise ReportValidationError("log.html is not available for this run")
        _open_path(Path(path))
        return Path(path)

    async def open_report(self, run_id: UUID) -> Path:
        run = await self.get_run(run_id)
        path = run.report_html
        if path is None or not Path(path).is_file():
            raise ReportValidationError("report.html is not available for this run")
        _open_path(Path(path))
        return Path(path)

    async def open_xml(self, run_id: UUID) -> Path:
        run = await self.get_run(run_id)
        path = run.output_xml
        if path is None or not Path(path).is_file():
            raise ReportValidationError("output.xml is not available for this run")
        _open_path(Path(path))
        return Path(path)

    async def reveal(self, run_id: UUID) -> Path:
        run = await self.get_run(run_id)
        directory = run.output_dir
        if directory is None or not Path(directory).is_dir():
            raise ReportValidationError("Report folder is not available for this run")
        _reveal_path(Path(directory))
        return Path(directory)

    async def dashboard(self) -> DashboardSummary:
        runs = await self.list_runs(limit=100)
        summary = self.results_store.dashboard_summary(runs)
        return DashboardSummary(
            total_runs=int(summary.get("total_runs") or 0),
            pass_rate=summary.get("pass_rate"),
            average_duration_ms=summary.get("average_duration_ms"),
            last_run=summary.get("last_run"),
            recent_runs=list(summary.get("recent_runs") or []),
            recent_failures=list(summary.get("recent_failures") or []),
        )


def _open_path(path: Path) -> None:
    if sys.platform == "darwin":
        subprocess.run(["open", str(path)], check=False)
    elif sys.platform == "win32":
        os.startfile(str(path))  # type: ignore[attr-defined]
    else:
        subprocess.run(["xdg-open", str(path)], check=False)


def _reveal_path(path: Path) -> None:
    target = Path(path)
    if sys.platform == "darwin":
        # Reveal a file when possible; otherwise open the folder.
        if target.is_file():
            subprocess.run(["open", "-R", str(target)], check=False)
        else:
            subprocess.run(["open", str(target)], check=False)
    elif sys.platform == "win32":
        if target.is_file():
            subprocess.run(["explorer", f"/select,{target}"], check=False)
        else:
            subprocess.run(["explorer", str(target)], check=False)
    else:
        folder = target if target.is_dir() else target.parent
        subprocess.run(["xdg-open", str(folder)], check=False)
