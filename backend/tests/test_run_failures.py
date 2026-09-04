"""Coverage for GET /analysis/execution/run-failures."""

from __future__ import annotations

import textwrap
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.domain.models import ExecutionRun, ExecutionStatus
from robot_studio.main import create_app


def _write_failing_output(path: Path) -> None:
    path.write_text(
        textwrap.dedent(
            """\
            <?xml version="1.0" encoding="UTF-8"?>
            <robot generator="Robot 7.0 (Python 3.12)" generated="20240101 00:00:00.000">
            <suite id="s1" name="Failing" source="/proj/tests/failing.robot">
            <test id="s1-t1" name="Broken Login" line="5">
            <kw name="Should Be Equal" owner="BuiltIn">
            <status status="FAIL" starttime="20240101 00:00:00.000" endtime="20240101 00:00:00.010" elapsed="0.010"/>
            </kw>
            <status status="FAIL" starttime="20240101 00:00:00.000" endtime="20240101 00:00:00.010" elapsed="0.010">
            Expected and actual did not match
            </status>
            </test>
            <test id="s1-t2" name="Still Ok" line="12">
            <status status="PASS" starttime="20240101 00:00:00.000" endtime="20240101 00:00:00.001" elapsed="0.001"/>
            </test>
            <status status="FAIL" starttime="20240101 00:00:00.000" endtime="20240101 00:00:00.010" elapsed="0.010"/>
            </suite>
            <statistics/>
            <errors/>
            </robot>
            """,
        ),
        encoding="utf-8",
    )


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
async def test_run_failures_lists_failed_tests_only(api_client) -> None:
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

    out = project_path / ".robotstudio" / "reports" / "Run-fail"
    out.mkdir(parents=True, exist_ok=True)
    output_xml = out / "output.xml"
    _write_failing_output(output_xml)

    run_id = uuid4()
    run = ExecutionRun(
        id=run_id,
        workspace_id=UUID(ws.json()["id"]),
        project_id=UUID(project_id),
        environment_id=uuid4(),
        project_name="Demo",
        suite="failing.robot",
        status=ExecutionStatus.FAILED,
        started_at=datetime.now(UTC),
        finished_at=datetime.now(UTC),
        duration_ms=10,
        exit_code=1,
        output_dir=out,
        output_xml=output_xml,
        total_tests=2,
        passed=1,
        failed=1,
        skipped=0,
    )
    assert fresh.execution_repository is not None
    await fresh.execution_repository.create(run)

    missing = await client.get(
        "/api/v1/analysis/execution/run-failures",
        params={"run_id": str(uuid4())},
    )
    assert missing.status_code == 400

    resp = await client.get(
        "/api/v1/analysis/execution/run-failures",
        params={"run_id": str(run_id)},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["run_id"] == str(run_id)
    assert len(body["items"]) == 1
    item = body["items"][0]
    assert item["name"] == "Broken Login"
    assert "did not match" in item["message"]
    assert item["source"].endswith("failing.robot")
    assert item["line"] == 5
    assert item["status"] == "FAIL"
