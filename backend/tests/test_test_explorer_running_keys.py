"""Unit tests for Test Explorer running-status key handling."""

from __future__ import annotations

from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.application.services.test_explorer_service import TestExplorerService
from robot_studio.core.events import (
    ExecutionCancelled,
    ExecutionStarted,
)
from robot_studio.domain.models import ExecutionStatus


def _bare_service() -> TestExplorerService:
    svc = object.__new__(TestExplorerService)
    svc._running_keys = set()
    svc._tree = object()
    svc._statuses = {}
    return svc


@pytest.mark.asyncio
async def test_execution_started_preserves_seeded_single_test_key() -> None:
    svc = _bare_service()
    key = f"{Path('/tmp/demo.robot').resolve()}::Alpha"
    svc._running_keys = {key}
    await TestExplorerService._on_execution_started(
        svc,
        ExecutionStarted(run_id=uuid4(), project_id=uuid4()),
    )
    assert svc._running_keys == {key}
    assert svc._tree is None


@pytest.mark.asyncio
async def test_execution_started_defaults_to_all_when_unseeded() -> None:
    svc = _bare_service()
    await TestExplorerService._on_execution_started(
        svc,
        ExecutionStarted(run_id=uuid4(), project_id=uuid4()),
    )
    assert svc._running_keys == {"*"}


@pytest.mark.asyncio
async def test_execution_cancelled_clears_running_keys() -> None:
    svc = _bare_service()
    svc._running_keys = {"*"}
    await TestExplorerService._on_execution_cancelled(
        svc,
        ExecutionCancelled(run_id=uuid4()),
    )
    assert svc._running_keys == set()
    assert svc._tree is None


def test_status_for_file_running_key_marks_suite_cases() -> None:
    svc = _bare_service()
    path = str(Path("/tmp/dashboard_test.robot").resolve())
    svc._running_keys = {TestExplorerService._file_running_key(path)}
    key = TestExplorerService._case_key(path, "TC-DASH-001")
    assert TestExplorerService._status_for(svc, key, "TC-DASH-001", path) == "running"
    other = str(Path("/tmp/other.robot").resolve())
    other_key = TestExplorerService._case_key(other, "Other")
    assert TestExplorerService._status_for(svc, other_key, "Other", other) == "not_run"


def test_status_for_single_case_key_does_not_mark_siblings() -> None:
    svc = _bare_service()
    path = str(Path("/tmp/dashboard_test.robot").resolve())
    only = TestExplorerService._case_key(path, "TC-DASH-001")
    svc._running_keys = {only}
    assert (
        TestExplorerService._status_for(svc, only, "TC-DASH-001", path) == "running"
    )
    sibling = TestExplorerService._case_key(path, "TC-DASH-002")
    assert (
        TestExplorerService._status_for(svc, sibling, "TC-DASH-002", path) == "not_run"
    )


class _FakeExecution:
    def __init__(self, status: ExecutionStatus) -> None:
        self._current = type("Run", (), {"status": status})()


def test_status_for_ignores_stale_keys_when_execution_finished() -> None:
    svc = _bare_service()
    svc.execution_service = _FakeExecution(ExecutionStatus.FINISHED)
    svc._running_keys = {"*"}
    path = str(Path("/tmp/dashboard_test.robot").resolve())
    key = TestExplorerService._case_key(path, "TC-DASH-001")
    assert TestExplorerService._status_for(svc, key, "TC-DASH-001", path) == "not_run"


def test_prune_stale_running_keys_when_execution_inactive() -> None:
    svc = _bare_service()
    svc.execution_service = _FakeExecution(ExecutionStatus.FINISHED)
    svc._running_keys = {"*"}
    TestExplorerService._prune_stale_running_keys(svc)
    assert svc._running_keys == set()
    assert svc._tree is None


def test_status_for_keeps_running_while_execution_active() -> None:
    svc = _bare_service()
    svc.execution_service = _FakeExecution(ExecutionStatus.RUNNING)
    svc._running_keys = {"*"}
    path = str(Path("/tmp/dashboard_test.robot").resolve())
    key = TestExplorerService._case_key(path, "TC-DASH-001")
    assert TestExplorerService._status_for(svc, key, "TC-DASH-001", path) == "running"
