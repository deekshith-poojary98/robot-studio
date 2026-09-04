"""Unit tests for Insights run-file path aggregation."""

from __future__ import annotations

import json
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


def test_aggregate_strips_suite_label_prefix() -> None:
    absolute = "/Users/me/proj/tests/login.robot"
    runs = [
        _run(suite="Suite: login.robot", failed=0, minutes_ago=1),
    ]
    composition = [FileComposition(file_path=absolute, counts={"test_case": 1})]

    _totals, _recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=composition,
    )

    assert len(files) == 1
    assert files[0].file_path == absolute
    assert files[0].passed == 1
    assert files[0].runs == 1


def test_aggregate_fans_out_project_run_from_file_outcomes(
    tmp_path,
) -> None:
    a = str(tmp_path / "tests" / "a.robot")
    b = str(tmp_path / "tests" / "b.robot")
    output_dir = tmp_path / "Run-1"
    output_dir.mkdir()
    (output_dir / "file_outcomes.json").write_text(
        json.dumps({"files": {a: "PASS", b: "FAIL"}}),
        encoding="utf-8",
    )
    runs = [
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
            duration_ms=900,
            exit_code=1,
            passed=1,
            failed=1,
            output_dir=output_dir,
        ),
    ]
    composition = [
        FileComposition(file_path=a, counts={"test_case": 1}),
        FileComposition(file_path=b, counts={"test_case": 1}),
    ]

    totals, _recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=composition,
    )

    # One project run overall; each leaf file gets its own outcome.
    assert totals.failed == 1
    assert totals.passed == 0
    by_path = {item.file_path: item for item in files}
    assert by_path[a].runs == 1 and by_path[a].passed == 1 and by_path[a].failed == 0
    assert by_path[b].runs == 1 and by_path[b].passed == 0 and by_path[b].failed == 1


def test_aggregate_prefers_file_outcomes_over_sole_robot(tmp_path) -> None:
    """A one-file project must not ignore file_outcomes and credit the run badge."""
    robot = str(tmp_path / "only.robot")
    output_dir = tmp_path / "Run-1"
    output_dir.mkdir()
    (output_dir / "file_outcomes.json").write_text(
        json.dumps({"files": {robot: "PASS"}}),
        encoding="utf-8",
    )
    runs = [
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
            duration_ms=400,
            exit_code=1,
            passed=0,
            failed=1,
            output_dir=output_dir,
        ),
    ]
    composition = [FileComposition(file_path=robot, counts={"test_case": 1})]

    _totals, _recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=composition,
    )

    assert len(files) == 1
    assert files[0].file_path == robot
    assert files[0].passed == 1
    assert files[0].failed == 0


def test_aggregate_credits_sole_robot_when_outcomes_missing() -> None:
    robot = "/proj/only.robot"
    runs = [
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
            duration_ms=400,
            exit_code=1,
            passed=0,
            failed=1,
        ),
    ]
    composition = [FileComposition(file_path=robot, counts={"test_case": 1})]

    _totals, _recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=composition,
    )

    assert len(files) == 1
    assert files[0].file_path == robot
    assert files[0].failed == 1
    assert files[0].runs == 1


def test_aggregate_builds_outcomes_for_every_cache_miss(tmp_path) -> None:
    a = str(tmp_path / "a.robot")
    b = str(tmp_path / "b.robot")

    def _xml(output_dir, a_status: str, b_status: str) -> None:
        output_dir.mkdir()
        (output_dir / "output.xml").write_text(
            "<?xml version='1.0'?>\n"
            "<robot><suite id='s1' name='Root'>\n"
            f"<suite id='s1-s1' name='A' source='{a}'>"
            f"<status status='{a_status}'/></suite>\n"
            f"<suite id='s1-s2' name='B' source='{b}'>"
            f"<status status='{b_status}'/></suite>\n"
            "<status status='FAIL'/></suite></robot>\n",
            encoding="utf-8",
        )

    first = tmp_path / "Run-1"
    second = tmp_path / "Run-2"
    _xml(first, "PASS", "FAIL")
    _xml(second, "PASS", "PASS")
    runs = [
        ExecutionRun(
            id=uuid4(),
            workspace_id=uuid4(),
            project_id=uuid4(),
            environment_id=uuid4(),
            project_name="Demo",
            suite="Project: Demo",
            status=ExecutionStatus.FAILED,
            started_at=datetime.now(UTC) - timedelta(minutes=2),
            finished_at=datetime.now(UTC) - timedelta(minutes=2),
            duration_ms=200,
            exit_code=1,
            passed=1,
            failed=1,
            output_dir=first,
        ),
        ExecutionRun(
            id=uuid4(),
            workspace_id=uuid4(),
            project_id=uuid4(),
            environment_id=uuid4(),
            project_name="Demo",
            suite="Project: Demo",
            status=ExecutionStatus.FINISHED,
            started_at=datetime.now(UTC),
            finished_at=datetime.now(UTC),
            duration_ms=200,
            exit_code=0,
            passed=2,
            failed=0,
            output_dir=second,
        ),
    ]
    composition = [
        FileComposition(file_path=a, counts={"test_case": 1}),
        FileComposition(file_path=b, counts={"test_case": 1}),
    ]

    _totals, _recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=composition,
    )

    by_path = {item.file_path: item for item in files}
    assert by_path[a].runs == 2 and by_path[a].passed == 2
    assert by_path[b].runs == 2 and by_path[b].passed == 1 and by_path[b].failed == 1
    assert (first / "file_outcomes.json").is_file()
    assert (second / "file_outcomes.json").is_file()


def test_aggregate_excludes_empty_runs_from_pass_rate() -> None:
    suite = "/proj/tests/demo.robot"
    runs = [
        _run(suite=suite, failed=0, minutes_ago=2),
        ExecutionRun(
            id=uuid4(),
            workspace_id=uuid4(),
            project_id=uuid4(),
            environment_id=uuid4(),
            project_name="Demo",
            suite=suite,
            status=ExecutionStatus.FAILED,
            started_at=datetime.now(UTC),
            finished_at=datetime.now(UTC),
            duration_ms=100,
            exit_code=1,
            passed=0,
            failed=None,
            total_tests=0,
            skipped=0,
        ),
    ]
    totals, recent, files = _aggregate_runs(
        runs,
        recent_limit=10,
        composition_files=[FileComposition(file_path=suite, counts={"test_case": 1})],
    )
    assert totals.passed == 1
    assert totals.failed == 0
    assert totals.pass_rate == 100.0
    assert recent[1].outcome == "NO TESTS"
    assert files[0].runs == 1
    assert files[0].passed == 1
