"""Unit tests for report indexing, deletion, and dashboard aggregation."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.application.services.report_service import (
    ReportService,
    ReportValidationError,
)
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import InMemoryEventBus, RunDeleted, RunIndexed, WorkspaceOpened
from robot_studio.domain.models import (
    ExecutionRun,
    ExecutionStatus,
    Workspace,
    WorkspaceSettings,
)
from robot_studio.infrastructure.execution.output_stats import parse_output_stats
from robot_studio.infrastructure.execution.results_store import FilesystemResultsStore
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
)


SAMPLE_OUTPUT_XML = """<?xml version="1.0" encoding="UTF-8"?>
<robot generator="Robot 7.0.1 (Python 3.12.0 on darwin)" generated="20260719 12:00:00.000000" rpa="false" schemaversion="5">
<suite id="s1" name="Demo" source="demo.robot">
<test id="s1-t1" name="Hello">
<status status="PASS" start="20260719 12:00:00.000000" elapsed="0.010"/>
</test>
<test id="s1-t2" name="Broken">
<status status="FAIL" start="20260719 12:00:00.010000" elapsed="0.020"/>
</test>
<status status="FAIL" start="20260719 12:00:00.000000" elapsed="0.030"/>
</suite>
<statistics>
<total>
<stat pass="1" fail="1" skip="0">All Tests</stat>
</total>
</statistics>
</robot>
"""


def _workspace(tmp_path: Path) -> Workspace:
    root = tmp_path / "WS"
    root.mkdir()
    (root / ".robotstudio" / "reports").mkdir(parents=True)
    return Workspace(
        id=uuid4(),
        name="WS",
        path=root,
        created_at=datetime.now(UTC),
        settings=WorkspaceSettings(),
    )


def _run(
    workspace: Workspace,
    *,
    status: ExecutionStatus = ExecutionStatus.FINISHED,
    exit_code: int = 0,
    failed: int | None = 0,
    passed: int | None = 1,
    duration_ms: int = 1000,
) -> ExecutionRun:
    return ExecutionRun(
        id=uuid4(),
        workspace_id=workspace.id,
        project_id=uuid4(),
        environment_id=uuid4(),
        project_name="Demo",
        suite="tests/demo.robot",
        status=status,
        started_at=datetime.now(UTC),
        finished_at=datetime.now(UTC),
        duration_ms=duration_ms,
        exit_code=exit_code,
        command="python -m robot",
        environment_name="robot-main",
        passed=passed,
        failed=failed,
        total_tests=(passed or 0) + (failed or 0),
        skipped=0,
    )


@pytest.fixture
async def report_stack(tmp_path: Path):
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    workspace = _workspace(tmp_path)
    await context.open(workspace)

    repository = SqliteExecutionRepository(tmp_path / "robot.db")
    await repository.initialize()
    store = FilesystemResultsStore()
    service = ReportService(
        context=context,
        event_bus=bus,
        results_store=store,
        repository=repository,
    )
    service.start()
    return service, repository, store, workspace, bus


def test_parse_output_stats(tmp_path: Path) -> None:
    path = tmp_path / "output.xml"
    path.write_text(SAMPLE_OUTPUT_XML, encoding="utf-8")
    stats = parse_output_stats(path)
    assert stats["passed"] == 1
    assert stats["failed"] == 1
    assert stats["skipped"] == 0
    assert stats["total_tests"] == 2
    assert stats["robot_version"] == "7.0.1"


@pytest.mark.asyncio
async def test_discover_run_indexes_artifacts(report_stack, tmp_path: Path) -> None:
    service, repository, store, workspace, bus = report_stack
    run_dir = workspace.path / ".robotstudio" / "reports" / "Run-20260719-120000"
    run_dir.mkdir(parents=True)
    (run_dir / "output.xml").write_text(SAMPLE_OUTPUT_XML, encoding="utf-8")
    (run_dir / "log.html").write_text("<html>log</html>", encoding="utf-8")
    (run_dir / "report.html").write_text("<html>report</html>", encoding="utf-8")

    run = _run(workspace)
    run = run.model_copy(update={"output_dir": run_dir})
    await repository.create(run)

    indexed_events: list[RunIndexed] = []

    async def on_indexed(event: RunIndexed) -> None:
        indexed_events.append(event)

    bus.subscribe(RunIndexed, on_indexed)

    indexed = await service.index_run(run.id)
    assert indexed is not None
    assert indexed.total_tests == 2
    assert indexed.passed == 1
    assert indexed.failed == 1
    assert indexed.robot_version == "7.0.1"
    assert indexed.log_html is not None
    assert indexed.report_html is not None
    assert len(indexed_events) == 1

    loaded = await store.load_run(run.id)
    assert loaded is not None
    assert loaded["passed"] == 1


@pytest.mark.asyncio
async def test_delete_run_removes_files_and_metadata(report_stack) -> None:
    service, repository, store, workspace, bus = report_stack
    run_dir = workspace.path / ".robotstudio" / "reports" / "Run-20260719-130000"
    run_dir.mkdir(parents=True)
    (run_dir / "report.html").write_text("<html/>", encoding="utf-8")

    run = _run(workspace)
    run = run.model_copy(update={"output_dir": run_dir, "report_html": run_dir / "report.html"})
    await repository.create(run)
    await store.discover_run(run.id, run_dir)

    deleted: list[RunDeleted] = []

    async def on_deleted(event: RunDeleted) -> None:
        deleted.append(event)

    bus.subscribe(RunDeleted, on_deleted)

    await service.delete_run(run.id)
    assert await repository.get(run.id) is None
    assert not run_dir.exists()
    assert await store.load_run(run.id) is None
    assert len(deleted) == 1


@pytest.mark.asyncio
async def test_dashboard_aggregation(report_stack) -> None:
    service, repository, _store, workspace, _bus = report_stack
    pass_run = _run(workspace, exit_code=0, failed=0, passed=2, duration_ms=1000)
    fail_run = _run(
        workspace,
        status=ExecutionStatus.FAILED,
        exit_code=1,
        failed=1,
        passed=0,
        duration_ms=2000,
    )
    await repository.create(pass_run)
    await repository.create(fail_run)

    summary = await service.dashboard()
    assert summary.total_runs == 2
    assert summary.pass_rate == 50.0
    assert summary.average_duration_ms == 1500.0
    assert summary.last_run is not None
    assert len(summary.recent_failures) == 1


@pytest.mark.asyncio
async def test_dashboard_does_not_treat_empty_selection_as_failure(report_stack) -> None:
    service, repository, _store, workspace, _bus = report_stack
    empty = _run(
        workspace,
        status=ExecutionStatus.FAILED,
        exit_code=252,
        failed=0,
        passed=0,
        duration_ms=200,
    )
    await repository.create(empty)

    summary = await service.dashboard()
    assert empty.result_badge() == "NO TESTS"
    assert summary.recent_failures == []
    assert summary.pass_rate is None

    crash = _run(
        workspace,
        status=ExecutionStatus.FAILED,
        exit_code=255,
        failed=0,
        passed=0,
        duration_ms=50,
    )
    assert crash.result_badge() == "ERROR"


@pytest.mark.asyncio
async def test_reopen_purges_missing_run_artifacts(report_stack) -> None:
    """Recreating a project at the same path must not revive ghost reports."""
    import shutil

    service, repository, _store, workspace, bus = report_stack
    run_dir = workspace.path / ".robotstudio" / "reports" / "Run-ghost"
    run_dir.mkdir(parents=True)
    (run_dir / "report.html").write_text("<html/>", encoding="utf-8")

    run = _run(workspace)
    run = run.model_copy(update={"output_dir": run_dir})
    await repository.create(run)
    assert len(await service.list_runs()) == 1

    shutil.rmtree(run_dir)
    assert len(await service.list_runs()) == 1  # mid-session list keeps the row

    deleted: list[RunDeleted] = []

    async def on_deleted(event: RunDeleted) -> None:
        deleted.append(event)

    bus.subscribe(RunDeleted, on_deleted)

    # Re-open same workspace id → WorkspaceOpened → purge_missing_runs.
    await bus.publish(WorkspaceOpened(workspace_id=workspace.id))

    assert await repository.get(run.id) is None
    assert await service.list_runs() == []
    assert len(deleted) == 1


@pytest.mark.asyncio
async def test_purge_workspace_runs_clears_registry(report_stack) -> None:
    service, repository, _store, workspace, _bus = report_stack
    run_dir = workspace.path / ".robotstudio" / "reports" / "Run-clear"
    run_dir.mkdir(parents=True)
    run = _run(workspace).model_copy(update={"output_dir": run_dir})
    await repository.create(run)

    removed = await service.purge_workspace_runs(workspace.id)
    assert removed >= 1
    assert await repository.get(run.id) is None
    assert await service.list_runs() == []


@pytest.mark.asyncio
async def test_get_missing_run_raises(report_stack) -> None:
    service, *_ = report_stack
    with pytest.raises(ReportValidationError):
        await service.get_run(uuid4())
