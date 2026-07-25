"""HTTP integration tests for environment endpoints."""

from pathlib import Path
import sys

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


@pytest.mark.asyncio
async def test_environment_api_flow(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()

    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code == 201

    created = await client.post(
        "/api/v1/environments",
        json={
            "name": "robot-main",
            "python_interpreter": sys.executable,
            "install_robot_framework": False,
        },
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["name"] == "robot-main"
    assert body["active"] is True
    assert body["python_executable"]

    listed = await client.get("/api/v1/environments")
    assert listed.status_code == 200
    assert len(listed.json()["environments"]) == 1

    second = await client.post(
        "/api/v1/environments",
        json={
            "name": "robot-alt",
            "python_interpreter": sys.executable,
            "install_robot_framework": False,
        },
    )
    assert second.status_code == 201
    second_id = second.json()["id"]

    activated = await client.post(
        "/api/v1/environments/activate",
        json={"environment_id": second_id},
    )
    assert activated.status_code == 200
    assert activated.json()["active"] is True

    detail = await client.get(f"/api/v1/environments/{second_id}")
    assert detail.status_code == 200
    assert detail.json()["name"] == "robot-alt"

    cloned = await client.post(
        f"/api/v1/environments/{second_id}/clone",
        json={"name": "robot-clone"},
    )
    assert cloned.status_code == 201
    assert cloned.json()["name"] == "robot-clone"

    # Cannot delete active
    blocked = await client.delete(f"/api/v1/environments/{second_id}")
    assert blocked.status_code == 400

    deleted = await client.delete(
        f"/api/v1/environments/{cloned.json()['id']}?delete_files=true",
    )
    assert deleted.status_code == 204


@pytest.mark.asyncio
async def test_list_python_interpreters(api_client) -> None:
    client, _fresh, _tmp = api_client
    response = await client.get("/api/v1/environments/interpreters")
    assert response.status_code == 200
    body = response.json()
    assert "interpreters" in body
    assert isinstance(body["interpreters"], list)
    assert len(body["interpreters"]) >= 1
    first = body["interpreters"][0]
    assert first["path"]
    assert first["version"]
    assert first["display_name"]


@pytest.mark.asyncio
async def test_health_still_ok(api_client) -> None:
    client, _fresh, _tmp = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
