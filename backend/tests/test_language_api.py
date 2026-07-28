"""HTTP tests for M10 language intelligence endpoints."""

from __future__ import annotations

from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.main import create_app

SAMPLE = """*** Settings ***
Library    Collections

*** Keywords ***
Hello World
    [Documentation]    Hi
    Log    hi

*** Test Cases ***
Run Hello
    Hello World
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


async def _open_workspace_with_suite(client: AsyncClient, tmp_path: Path) -> Path:
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
    suite.write_text(SAMPLE, encoding="utf-8")

    rebuilt = await client.post("/api/v1/index/rebuild")
    assert rebuilt.status_code == 200
    return suite


@pytest.mark.asyncio
async def test_language_completion_api(api_client) -> None:
    client, _fresh, tmp_path = api_client
    suite = await _open_workspace_with_suite(client, tmp_path)

    response = await client.post(
        "/api/v1/language/completion",
        json={
            "file_path": str(suite),
            "line": 10,
            "column": 5,
            "content": SAMPLE,
            "query": "Hel",
        },
    )
    assert response.status_code == 200
    labels = [item["label"] for item in response.json()["items"]]
    assert "Hello World" in labels


@pytest.mark.asyncio
async def test_language_diagnostics_api(api_client) -> None:
    client, _fresh, tmp_path = api_client
    suite = await _open_workspace_with_suite(client, tmp_path)
    broken = SAMPLE + "\n*** Test Cases ***\nBroken\n    Unknown Keyword\n"

    response = await client.post(
        "/api/v1/language/diagnostics",
        json={"file_path": str(suite), "content": broken},
    )
    assert response.status_code == 200
    messages = [item["message"] for item in response.json()["diagnostics"]]
    assert any("Unknown keyword" in msg for msg in messages)
    assert not any("Unknown keyword '[Documentation]'" in msg for msg in messages)


@pytest.mark.asyncio
async def test_language_diagnostics_ignores_local_settings(api_client) -> None:
    client, _fresh, tmp_path = api_client
    suite = await _open_workspace_with_suite(client, tmp_path)
    content = """*** Test Cases ***
Example Test
    [Documentation]    Example test case
    [Tags]    smoke
    Log    Hello

*** Keywords ***
Example Keyword
    [Documentation]    Example reusable keyword
    [Arguments]    ${name}
    Log    ${name}
"""

    response = await client.post(
        "/api/v1/language/diagnostics",
        json={"file_path": str(suite), "content": content},
    )
    assert response.status_code == 200
    messages = [item["message"] for item in response.json()["diagnostics"]]
    assert not any("Unknown keyword '[Documentation]'" in msg for msg in messages)
    assert not any("Unknown keyword '[Tags]'" in msg for msg in messages)
    assert not any("Unknown keyword '[Arguments]'" in msg for msg in messages)


@pytest.mark.asyncio
async def test_language_format_api(api_client) -> None:
    client, _fresh, tmp_path = api_client
    suite = await _open_workspace_with_suite(client, tmp_path)
    messy = "*** Keywords ***\nHello World   \n    Log    hi   \n"

    response = await client.post(
        "/api/v1/language/format",
        json={"file_path": str(suite), "content": messy},
    )
    assert response.status_code == 200
    formatted = response.json()["content"]
    assert "Hello World" in formatted
    assert not formatted.endswith("   \n")


@pytest.mark.asyncio
async def test_language_signature_help_api(api_client) -> None:
    client, _fresh, tmp_path = api_client
    suite = await _open_workspace_with_suite(client, tmp_path)

    response = await client.post(
        "/api/v1/language/signature-help",
        json={
            "file_path": str(suite),
            "line": 11,
            "column": 10,
            "content": SAMPLE,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body is None or body["keyword"] == "Hello World"


@pytest.mark.asyncio
async def test_language_requires_workspace(api_client) -> None:
    client, _fresh, _tmp = api_client

    response = await client.post(
        "/api/v1/language/completion",
        json={"file_path": "/tmp/x.robot", "content": "", "line": 1, "column": 1},
    )
    assert response.status_code == 400
