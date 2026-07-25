"""HTTP integration tests for execution endpoints."""

from pathlib import Path
import sys
import asyncio

import pytest
from httpx import ASGITransport, AsyncClient

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.main import create_app


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


async def _wait_status(client: AsyncClient, timeout: float = 60.0) -> dict:
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        response = await client.get("/api/v1/execution/status")
        assert response.status_code == 200
        body = response.json()
        if body["status"] in {"finished", "failed", "cancelled"}:
            return body
        await asyncio.sleep(0.15)
    raise TimeoutError("execution status wait timed out")


@pytest.mark.asyncio
async def test_execution_api_flow(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()

    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code == 201

    env = await client.post(
        "/api/v1/environments",
        json={
            "name": "robot-env",
            "python_interpreter": sys.executable,
            "install_robot_framework": True,
        },
    )
    assert env.status_code == 201, env.text

    project = await client.post(
        "/api/v1/projects",
        json={"name": "Demo"},
    )
    assert project.status_code == 201
    project_path = Path(project.json()["path"])
    suite = project_path / "tests" / "sample.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Test Cases ***\nHello\n    Log    via api\n",
        encoding="utf-8",
    )

    idle = await client.get("/api/v1/execution/status")
    assert idle.status_code == 200
    assert idle.json()["status"] == "idle"

    started = await client.post(
        "/api/v1/execution/run",
        json={"file": str(suite)},
    )
    assert started.status_code == 200, started.text
    assert started.json()["status"] == "running"

    final = await _wait_status(client)
    assert final["status"] == "finished"
    assert final["run"]["exit_code"] == 0

    history = await client.get("/api/v1/execution/history")
    assert history.status_code == 200
    assert len(history.json()["runs"]) >= 1


@pytest.mark.asyncio
async def test_health_still_ok(api_client) -> None:
    client, _fresh, _tmp = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
