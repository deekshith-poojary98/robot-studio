"""Unit tests for Insights run-file path aggregation."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import uuid4

from robot_studio.application.services.insights_service import _aggregate_runs
from robot_studio.domain.models import ExecutionRun, ExecutionStatus
from robot_studio.domain.models.insights import FileComposition


def _run(*, suite: str, failed: int, minutes_ago: int = 0) -> ExecutionRun:
    now = datetime.now(UTC)
    started = now - timedelta(minutes=minutes_ago)
    return ExecutionRun(
        id=uuid4(),
        workspace_id=uuid4(),
        project_id=uuid4(),
        environment_id=uuid4(),
        project_name="Demo",
        suite=suite,
        status=ExecutionStatus.FAILED if failed else ExecutionStatus.FINISHED,
        started_at=started,
        finished_at=started,
        duration_ms=1000,
        exit_code=1 if failed else 0,
        passed=0 if failed else 1,
        failed=failed,
    )


def test_aggregate_merges_basename_and_absolute_suite_paths() -> None:
    absolute = "/Users/me/proj/tests/login.robot"
    runs = [
        _run(suite=absolute, failed=1, minutes_ago=4),
        _run(suite="login.robot", failed=1, minutes_ago=3),
        _run(suite="tests/login.robot", failed=1, minutes_ago=2),
        _run(suite=absolute, failed=0, minutes_ago=1),
    ]
    composition = [FileComposition(file_path=absolute, counts={"test_case": 1})]

    totals, _recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=composition,
    )

    assert totals.failed == 3
    assert totals.passed == 1
    assert len(files) == 1
    assert files[0].file_path == absolute
    assert files[0].failed == 3
    assert files[0].runs == 4


def test_aggregate_keeps_distinct_same_basename_in_different_folders() -> None:
    a = "/proj/a/login.robot"
    b = "/proj/b/login.robot"
    runs = [
        _run(suite=a, failed=1, minutes_ago=2),
        _run(suite=b, failed=1, minutes_ago=1),
    ]
    composition = [
        FileComposition(file_path=a, counts={}),
        FileComposition(file_path=b, counts={}),
    ]

    _totals, _recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=composition,
    )

    paths = sorted(item.file_path for item in files)
    assert paths == sorted([a, b])
    assert all(item.failed == 1 and item.runs == 1 for item in files)


def test_aggregate_merges_without_composition_via_suffix() -> None:
    absolute = "/Users/me/proj/tests/login.robot"
    runs = [
        _run(suite=absolute, failed=1, minutes_ago=2),
        _run(suite="login.robot", failed=1, minutes_ago=1),
    ]

    _totals, _recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=[],
    )

    assert len(files) == 1
    assert files[0].file_path == absolute
    assert files[0].failed == 2
    assert files[0].runs == 2


def test_aggregate_folds_project_label_into_sole_file_without_composition() -> None:
    absolute = "/Users/me/proj/tests/login.robot"
    runs = [
        _run(suite=absolute, failed=0, minutes_ago=2),
        ExecutionRun(
            id=uuid4(),
            workspace_id=uuid4(),
            project_id=uuid4(),
            environment_id=uuid4(),
            project_name="Demo",
            suite="Project: Demo",
            status=ExecutionStatus.FAILED,
            started_at=datetime.now(UTC),
            finished_at=datetime.now(UTC),
            duration_ms=500,
            exit_code=1,
            passed=0,
            failed=1,
        ),
    ]

    _totals, _recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=[],
    )

    assert len(files) == 1
    assert files[0].file_path == absolute
    assert files[0].runs == 2
    assert files[0].failed == 1
    assert files[0].passed == 1
