"""Tests for Execution Knowledge Layer (ExecutionLinker + /analysis/execution/*)."""

from __future__ import annotations

import subprocess
import textwrap
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.domain.models import ExecutionRun, ExecutionStatus
from robot_studio.infrastructure.execution.execution_trace import (
    flatten_keyword_steps,
    iter_tests,
    parse_execution_trace,
)
from robot_studio.main import create_app

ROBOT_BIN = Path(__file__).resolve().parents[1] / ".venv" / "bin" / "robot"


def _write_suite(project_path: Path) -> Path:
    resource = project_path / "resources" / "common.resource"
    resource.parent.mkdir(parents=True, exist_ok=True)
    resource.write_text(
        textwrap.dedent(
            """\
            *** Keywords ***
            Login User
                Log    login

            Dead Keyword
                No Operation
            """,
        ),
        encoding="utf-8",
    )
    suite = project_path / "tests" / "login.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        textwrap.dedent(
            """\
            *** Settings ***
            Resource    ../resources/common.resource

            *** Test Cases ***
            Can Login
                Login User
                Log    done
            """,
        ),
        encoding="utf-8",
    )
    return suite


def test_parse_execution_trace_keywords(tmp_path: Path) -> None:
    suite = tmp_path / "demo.robot"
    suite.write_text(
        "*** Test Cases ***\nDemo\n    Log    hi\n",
        encoding="utf-8",
    )
    out = tmp_path / "out"
    out.mkdir()
    subprocess.run(
        [str(ROBOT_BIN), "-d", str(out), str(suite)],
        check=True,
        capture_output=True,
    )
    trace = parse_execution_trace(out / "output.xml")
    assert trace is not None
    pairs = iter_tests(trace)
    assert len(pairs) == 1
    _suite, test = pairs[0]
    assert test.name == "Demo"
    assert test.status == "PASS"
    flat = flatten_keyword_steps(test.keywords)
    assert any(s.name == "Log" for s in flat)


@pytest.fixture
async def api_client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "data_dir", tmp_path / "data")
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    fresh = Container()
    await fresh.initialize_async()
    app = create_app()
    app.dependency_overrides[get_gateway] = lambda: RestGateway(fresh)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        try:
            yield client, fresh, tmp_path
        finally:
            await fresh.shutdown()
    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_execution_knowledge_apis(api_client) -> None:
    client, fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code == 201
    project = await client.post("/api/v1/projects", json={"name": "Demo"})
    assert project.status_code == 201
    project_path = Path(project.json()["path"])
    project_id = project.json()["id"]
    suite = _write_suite(project_path)

    rebuilt = await client.post("/api/v1/index/rebuild?wait=true")
    assert rebuilt.status_code == 200, rebuilt.text

    out = project_path / ".robotstudio" / "reports" / "Run-test"
    out.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [str(ROBOT_BIN), "-d", str(out), str(suite)],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    output_xml = out / "output.xml"
    assert output_xml.is_file()

    run_id = uuid4()
    run = ExecutionRun(
        id=run_id,
        workspace_id=UUID_from(ws.json()["id"]),
        project_id=UUID_from(project_id),
        environment_id=uuid4(),
        project_name="Demo",
        suite=str(suite),
        status=ExecutionStatus.FINISHED,
        started_at=datetime.now(UTC),
        finished_at=datetime.now(UTC),
        duration_ms=100,
        exit_code=0,
        output_dir=out,
        output_xml=output_xml,
        total_tests=1,
        passed=1,
        failed=0,
        skipped=0,
    )
    assert fresh.execution_repository is not None
    await fresh.execution_repository.create(run)

    linked = await client.post(f"/api/v1/analysis/execution/link/{run_id}")
    assert linked.status_code == 200, linked.text
    assert linked.json()["test_count"] >= 1
    assert linked.json()["graph_version"]

    snap = await client.get("/api/v1/analysis/execution/snapshot")
    assert snap.status_code == 200
    assert snap.json()["linked_runs"] >= 1
    assert snap.json()["entities_with_stats"] >= 1

    test_hist = await client.get(
        "/api/v1/analysis/execution/test-history",
        params={"test": "Can Login"},
    )
    assert test_hist.status_code == 200
    assert len(test_hist.json()["items"]) >= 1
    assert test_hist.json()["items"][0]["status"] == "PASS"

    kw_hist = await client.get(
        "/api/v1/analysis/execution/keyword-history",
        params={"keyword": "Login User"},
    )
    assert kw_hist.status_code == 200
    assert len(kw_hist.json()["items"]) >= 1

    never = await client.get("/api/v1/analysis/execution/never-executed-keywords")
    assert never.status_code == 200
    never_names = {i["name"] for i in never.json()["items"]}
    assert "Dead Keyword" in never_names
    assert "Login User" not in never_names

    most = await client.get("/api/v1/analysis/execution/most-executed-keywords")
    assert most.status_code == 200
    assert any(i["execution_count"] >= 1 for i in most.json()["items"])

    slow_kw = await client.get("/api/v1/analysis/execution/slowest-keywords")
    assert slow_kw.status_code == 200

    slow_tests = await client.get("/api/v1/analysis/execution/slowest-tests")
    assert slow_tests.status_code == 200
    assert any(i["entity"]["name"] == "Can Login" for i in slow_tests.json()["items"])

    heat = await client.get("/api/v1/analysis/execution/heat-map")
    assert heat.status_code == 200

    flaky = await client.get("/api/v1/analysis/execution/flaky-candidates")
    assert flaky.status_code == 200
    # Single pass run → no flaky candidates yet
    assert isinstance(flaky.json()["items"], list)

    failures = await client.get("/api/v1/analysis/execution/last-failures")
    assert failures.status_code == 200
    assert failures.json()["items"] == []


def UUID_from(value: str):
    from uuid import UUID

    return UUID(value)
