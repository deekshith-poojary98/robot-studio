"""Report and run-index use cases built on ExecutionRepository + ResultsStore."""

from __future__ import annotations

import asyncio
import os
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import TYPE_CHECKING
from uuid import UUID

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import (
    EventBus,
    ExecutionCancelled,
    ExecutionFailed,
    ExecutionFinished,
    RunDeleted,
    RunIndexed,
    SettingsUpdated,
    WorkspaceOpened,
)
from robot_studio.domain.interfaces.runner import ResultsStore
from robot_studio.domain.models import DashboardSummary, ExecutionRun
from robot_studio.infrastructure.execution.reportlens import (
    REPORTLENS_HTML_NAME,
    generate_reportlens_html,
    reportlens_needs_rebuild,
)
from robot_studio.infrastructure.execution.results_store import FilesystemResultsStore
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
)

if TYPE_CHECKING:
    from robot_studio.application.services.settings_service import SettingsService


class ReportValidationError(Exception):
    """Raised when a report operation cannot proceed."""


@dataclass
class ReportService:
    context: WorkspaceContext
    event_bus: EventBus
    results_store: ResultsStore
    repository: SqliteExecutionRepository
    settings_service: SettingsService | None = None
    _subscribed: bool = field(default=False, init=False)

    def start(self) -> None:
        if self._subscribed:
            return
        self.event_bus.subscribe(ExecutionFinished, self._on_execution_finished)
        self.event_bus.subscribe(ExecutionFailed, self._on_execution_failed)
        self.event_bus.subscribe(ExecutionCancelled, self._on_execution_cancelled)
        self.event_bus.subscribe(WorkspaceOpened, self._on_workspace_opened)
        self.event_bus.subscribe(SettingsUpdated, self._on_settings_updated)
        self._subscribed = True

    async def _on_workspace_opened(self, event: WorkspaceOpened) -> None:
        workspace = self.context.workspace
        if workspace is not None and workspace.id == event.workspace_id:
            await self.relocate_run_paths(workspace.id, workspace.path)
        await self.purge_missing_runs(event.workspace_id)
        await self.purge_expired_runs(event.workspace_id)

    async def _on_settings_updated(self, _event: SettingsUpdated) -> None:
        workspace = self.context.workspace
        if workspace is None:
            return
        await self.purge_expired_runs(workspace.id)

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
        from robot_studio.domain.models import ExecutionStatus

        runs = await self.repository.list_by_workspace(workspace.id, limit=limit * 2)
        return [r for r in runs if r.status != ExecutionStatus.ABORTED][:limit]

    async def purge_missing_runs(self, workspace_id: UUID) -> list[UUID]:
        """Drop run rows whose on-disk output directories no longer exist."""
        removed: list[UUID] = []
        runs = await self.repository.list_by_workspace(workspace_id, limit=10_000)
        for run in runs:
            if run.output_dir is not None and run.output_dir.is_dir():
                continue
            await self._erase_run(run)
            removed.append(run.id)
        return removed

    async def purge_expired_runs(self, workspace_id: UUID) -> list[UUID]:
        """Delete runs older than Settings → Execution → Report Retention Days.

        ``report_retention_days <= 0`` disables auto-delete. Removed runs leave
        Insights / analytics history as well (same path as manual Delete Run).
        """
        if self.settings_service is None:
            return []
        days = int(self.settings_service.get().execution.report_retention_days)
        if days <= 0:
            return []
        cutoff = datetime.now(UTC) - timedelta(days=days)
        removed: list[UUID] = []
        runs = await self.repository.list_by_workspace(workspace_id, limit=10_000)
        for run in runs:
            anchor = run.finished_at or run.started_at
            if anchor.tzinfo is None:
                anchor = anchor.replace(tzinfo=UTC)
            else:
                anchor = anchor.astimezone(UTC)
            if anchor >= cutoff:
                continue
            await self._erase_run(run)
            removed.append(run.id)
        return removed

    async def relocate_run_paths(
        self,
        workspace_id: UUID,
        workspace_path: Path,
    ) -> int:
        """Rewrite run artifact paths when the workspace folder was moved."""
        from robot_studio.infrastructure.workspace.filesystem import studio_reports_root

        reports_root = studio_reports_root(workspace_path)
        relocated = 0
        runs = await self.repository.list_by_workspace(workspace_id, limit=10_000)
        for run in runs:
            if run.output_dir is None or run.output_dir.is_dir():
                continue
            candidate = reports_root / run.output_dir.name
            if not candidate.is_dir():
                continue
            old_output = run.output_dir

            def _remap(
                path: Path | None,
                *,
                _old_output: Path = old_output,
                _candidate: Path = candidate,
            ) -> Path | None:
                if path is None:
                    return None
                try:
                    relative = path.relative_to(_old_output)
                except ValueError:
                    return _candidate / path.name
                return _candidate / relative

            updated = run.model_copy(
                update={
                    "output_dir": candidate.resolve(),
                    "output_xml": _remap(run.output_xml),
                    "log_html": _remap(run.log_html),
                    "report_html": _remap(run.report_html),
                },
            )
            await self.repository.update(updated)
            relocated += 1
        return relocated

    async def purge_workspace_runs(self, workspace_id: UUID) -> int:
        """Remove every run row for a workspace (root deleted externally)."""
        runs = await self.repository.list_by_workspace(workspace_id, limit=10_000)
        if not runs:
            return 0
        for run in runs:
            await self.results_store.delete_run(run.id, run.output_dir)
        count = await self.repository.delete_by_workspace(workspace_id)
        for run in runs:
            await self.event_bus.publish(
                RunDeleted(run_id=run.id, workspace_id=workspace_id),
            )
        return count

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

    async def _erase_run(self, run: ExecutionRun) -> None:
        await self.results_store.delete_run(run.id, run.output_dir)
        await self.repository.delete(run.id)
        await self.event_bus.publish(
            RunDeleted(run_id=run.id, workspace_id=run.workspace_id),
        )

    async def delete_run(self, run_id: UUID) -> None:
        workspace = self._require_workspace()
        run = await self.repository.get(run_id)
        if run is None:
            raise ReportValidationError(f"Run not found: {run_id}")
        if run.workspace_id != workspace.id:
            raise ReportValidationError("Run does not belong to the active workspace")
        await self._erase_run(run)

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

    async def open_reportlens(self, run_id: UUID) -> Path:
        """Generate ReportLens HTML from output.xml (if needed) and open it."""
        run = await self.get_run(run_id)
        xml = run.output_xml
        if xml is None or not Path(xml).is_file():
            raise ReportValidationError(
                "output.xml is not available — cannot generate ReportLens",
            )
        xml_path = Path(xml)
        out_dir = Path(run.output_dir) if run.output_dir is not None else xml_path.parent
        html_path = out_dir / REPORTLENS_HTML_NAME
        try:
            if reportlens_needs_rebuild(xml_path, html_path):
                await asyncio.to_thread(generate_reportlens_html, xml_path, html_path)
        except ReportValidationError:
            raise
        except Exception as exc:  # noqa: BLE001 — surface as user-facing validation
            raise ReportValidationError(
                f"ReportLens generation failed: {exc}",
            ) from exc
        if not html_path.is_file():
            raise ReportValidationError("ReportLens HTML was not created")
        _open_path(html_path)
        return html_path

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
