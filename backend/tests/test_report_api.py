"""HTTP integration tests for report endpoints."""

from __future__ import annotations

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
from robot_studio.main import create_app

SAMPLE_OUTPUT_XML = """<?xml version="1.0" encoding="UTF-8"?>
<robot generator="Robot 7.1.0 (Python 3.12.0 on darwin)" generated="20260719 12:00:00.000000">
<statistics>
<total>
<stat pass="2" fail="0" skip="0">All Tests</stat>
</total>
</statistics>
</robot>
"""


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


async def _open_workspace(client: AsyncClient, tmp_path: Path) -> Path:
    location = tmp_path / "homes"
    location.mkdir(exist_ok=True)
    response = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert response.status_code == 201
    return Path(response.json()["path"])


@pytest.mark.asyncio
async def test_reports_api_list_get_dashboard_delete(api_client, monkeypatch) -> None:
    client, fresh, tmp_path = api_client
    workspace_path = await _open_workspace(client, tmp_path)

    # Legacy root Reports/ still works for indexed runs (absolute output_dir).
    # New runs write under .robotstudio/reports — exercise that layout here.
    run_dir = workspace_path / ".robotstudio" / "reports" / "Run-20260719-140000"
    run_dir.mkdir(parents=True)
    (run_dir / "output.xml").write_text(SAMPLE_OUTPUT_XML, encoding="utf-8")
    (run_dir / "log.html").write_text("<html>log</html>", encoding="utf-8")
    (run_dir / "report.html").write_text("<html>report</html>", encoding="utf-8")

    workspace = fresh.workspace_context.workspace
    assert workspace is not None
    assert fresh.execution_repository is not None
    assert fresh.report_service is not None

    run = ExecutionRun(
        id=uuid4(),
        workspace_id=workspace.id,
        project_id=uuid4(),
        environment_id=uuid4(),
        project_name="Demo",
        suite="tests/demo.robot",
        status=ExecutionStatus.FINISHED,
        started_at=datetime.now(UTC),
        finished_at=datetime.now(UTC),
        duration_ms=1200,
        exit_code=0,
        command="python -m robot",
        output_dir=run_dir,
        environment_name="robot-main",
    )
    await fresh.execution_repository.create(run)
    await fresh.report_service.index_run(run.id)

    listed = await client.get("/api/v1/reports")
    assert listed.status_code == 200
    assert len(listed.json()["runs"]) == 1
    assert listed.json()["runs"][0]["robot_version"] == "7.1.0"

    detail = await client.get(f"/api/v1/reports/{run.id}")
    assert detail.status_code == 200
    body = detail.json()
    assert body["passed"] == 2
    assert body["failed"] == 0
    assert body["total_tests"] == 2

    dashboard = await client.get("/api/v1/reports/dashboard")
    assert dashboard.status_code == 200
    assert dashboard.json()["total_runs"] == 1
    assert dashboard.json()["pass_rate"] == 100.0

    opened: list[str] = []

    def fake_open(path: Path) -> None:
        opened.append(f"open:{path}")

    def fake_reveal(path: Path) -> None:
        opened.append(f"reveal:{path}")

    monkeypatch.setattr(
        "robot_studio.application.services.report_service._open_path",
        fake_open,
    )
    monkeypatch.setattr(
        "robot_studio.application.services.report_service._reveal_path",
        fake_reveal,
    )

    log = await client.post(f"/api/v1/reports/{run.id}/open-log")
    report = await client.post(f"/api/v1/reports/{run.id}/open-report")
    xml = await client.post(f"/api/v1/reports/{run.id}/open-xml")
    reveal = await client.post(f"/api/v1/reports/{run.id}/reveal")
    assert log.status_code == 200
    assert report.status_code == 200
    assert xml.status_code == 200
    assert reveal.status_code == 200
    assert any(item.startswith("open:") for item in opened)
    assert any(item.startswith("reveal:") for item in opened)

    deleted = await client.delete(f"/api/v1/reports/{run.id}")
    assert deleted.status_code == 204
    assert not run_dir.exists()

    empty = await client.get("/api/v1/reports")
    assert empty.status_code == 200
    assert empty.json()["runs"] == []


@pytest.mark.asyncio
async def test_health_unchanged(api_client) -> None:
    client, _fresh, _tmp = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "reports" in body["modules"]
    assert "execution" in body["modules"]
