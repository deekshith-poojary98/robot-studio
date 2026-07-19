"""API tests for file ops and document symbols."""

from __future__ import annotations

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
async def test_files_and_document_symbols(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code == 201

    project = await client.post(
        "/api/v1/projects",
        json={"name": "Demo", "type": "empty"},
    )
    assert project.status_code == 201
    suite = Path(project.json()["path"]) / "tests" / "demo.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Keywords ***\nHello World\n    Log    hi\n",
        encoding="utf-8",
    )

    tree = await client.get("/api/v1/files/tree", params={"depth": 4})
    assert tree.status_code == 200
    assert any(item["name"] == "Projects" for item in tree.json()["entries"])

    content = await client.get("/api/v1/files/content", params={"path": str(suite)})
    assert content.status_code == 200
    assert "Hello World" in content.json()["content"]

    written = await client.put(
        "/api/v1/files/content",
        json={"path": str(suite), "content": "*** Keywords ***\nUpdated\n    Log    x\n"},
    )
    assert written.status_code == 200
    assert suite.read_text(encoding="utf-8").startswith("*** Keywords ***")

    rebuild = await client.post("/api/v1/index/rebuild")
    assert rebuild.status_code == 200

    symbols = await client.get(
        "/api/v1/language/document-symbols",
        params={"file": str(suite)},
    )
    assert symbols.status_code == 200
    names = [item["name"] for item in symbols.json()["results"]]
    assert "Updated" in names

    workspace = await client.get(
        "/api/v1/language/workspace-symbols",
        params={"q": "Updated"},
    )
    assert workspace.status_code == 200
    assert any(item["name"] == "Updated" for item in workspace.json()["results"])
