"""HTTP tests for index / search / language endpoints."""

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
        try:
            yield client, fresh, tmp_path
        finally:
            await fresh.shutdown()
    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_index_search_language_api(api_client) -> None:
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
        json={"name": "Demo"},
    )
    assert project.status_code == 201
    project_path = Path(project.json()["path"])
    suite = project_path / "tests" / "demo.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Keywords ***\nHello World\n    [Documentation]    Hi\n    Log    hi\n\n"
        "*** Test Cases ***\nRun Hello\n    Hello World\n",
        encoding="utf-8",
    )

    rebuilt = await client.post("/api/v1/index/rebuild")
    assert rebuilt.status_code == 200, rebuilt.text
    assert rebuilt.json()["state"] == "ready"
    assert rebuilt.json()["files_indexed"] >= 1

    status = await client.get("/api/v1/index/status")
    assert status.status_code == 200
    assert status.json()["keywords_indexed"] >= 1

    search = await client.get("/api/v1/search", params={"q": "Hello", "kind": "keyword"})
    assert search.status_code == 200
    names = [item["name"] for item in search.json()["results"]]
    assert "Hello World" in names

    builtin = await client.get("/api/v1/search", params={"q": "Log", "kind": "keyword"})
    assert builtin.status_code == 200
    builtin_names = [item["name"] for item in builtin.json()["results"]]
    assert "Log" in builtin_names

    suites = await client.get("/api/v1/search", params={"q": "", "kind": "test_suite"})
    assert suites.status_code == 200
    assert len(suites.json()["results"]) >= 1

    definition = await client.get(
        "/api/v1/language/definition",
        params={"name": "Hello World"},
    )
    assert definition.status_code == 200
    assert definition.json()["name"] == "Hello World"

    hover = await client.get(
        "/api/v1/language/hover",
        params={"name": "Hello World"},
    )
    assert hover.status_code == 200
    assert "Hi" in hover.json()["documentation"]

    refs = await client.get(
        "/api/v1/language/references",
        params={"name": "Hello World"},
    )
    assert refs.status_code == 200
    assert len(refs.json()["references"]) >= 1


@pytest.mark.asyncio
async def test_health_unchanged_with_index_routes(api_client) -> None:
    client, _fresh, _tmp = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "keywords" in body["modules"]
    assert "libraries" in body["modules"]
