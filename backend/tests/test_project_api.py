"""HTTP integration tests for project endpoints."""

from pathlib import Path

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
        yield client, fresh, tmp_path

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_project_api_flow(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()

    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code == 201

    created = await client.post(
        "/api/v1/projects",
        json={"name": "Demo", "type": "browser"},
    )
    assert created.status_code == 201
    body = created.json()
    assert body["name"] == "Demo"
    assert body["type"] == "browser"

    listed = await client.get("/api/v1/projects")
    assert listed.status_code == 200
    assert len(listed.json()["projects"]) == 1

    recent = await client.get("/api/v1/projects/recent")
    assert recent.status_code == 200
    assert recent.json()["projects"][0]["name"] == "Demo"

    external = tmp_path / "Ext"
    external.mkdir()
    (external / "suite.robot").write_text("*** Test Cases ***\nA\n    No Operation\n")
    imported = await client.post(
        "/api/v1/projects/import",
        json={"path": str(external)},
    )
    assert imported.status_code == 200
    assert imported.json()["type"] == "imported"

    opened = await client.post(
        "/api/v1/projects/open",
        json={"project_id": body["id"]},
    )
    assert opened.status_code == 200


@pytest.mark.asyncio
async def test_health_still_ok(api_client) -> None:
    client, _, _ = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
