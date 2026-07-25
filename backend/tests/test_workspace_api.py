"""HTTP integration tests for workspace endpoints."""

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
        try:
            yield client
        finally:
            await fresh.shutdown()
    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_workspace_api_create_open_recent(
    api_client: AsyncClient,
    tmp_path: Path,
) -> None:
    location = tmp_path / "homes"
    location.mkdir()

    create_response = await api_client.post(
        "/api/v1/workspaces",
        json={"name": "Demo", "location": str(location)},
    )
    assert create_response.status_code == 201
    body = create_response.json()
    assert body["name"] == "Demo"
    assert body["path"] == str(location / "Demo")

    recent_response = await api_client.get("/api/v1/workspaces/recent")
    assert recent_response.status_code == 200
    recent = recent_response.json()["workspaces"]
    assert len(recent) == 1
    assert recent[0]["name"] == "Demo"

    open_response = await api_client.post(
        "/api/v1/workspaces/open",
        json={"path": body["path"]},
    )
    assert open_response.status_code == 200
    assert open_response.json()["id"] == body["id"]


@pytest.mark.asyncio
async def test_open_invalid_workspace_returns_400(
    api_client: AsyncClient,
    tmp_path: Path,
) -> None:
    response = await api_client.post(
        "/api/v1/workspaces/open",
        json={"path": str(tmp_path)},
    )
    assert response.status_code == 400
    assert "not a Robot Studio workspace" in response.json()["detail"]
