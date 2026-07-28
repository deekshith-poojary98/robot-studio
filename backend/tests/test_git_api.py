"""API tests for Git endpoints."""

from __future__ import annotations

import subprocess
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


def _git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=str(cwd), check=True, capture_output=True)


@pytest.mark.asyncio
async def test_git_status_not_repository(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code == 201

    response = await client.get("/api/v1/git/status")
    assert response.status_code == 200
    body = response.json()
    assert body["repository"]["is_repository"] is False


@pytest.mark.asyncio
async def test_git_init_commit_history_diff(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    workspace_path = Path(ws.json()["path"])

    init = await client.post("/api/v1/git/init")
    assert init.status_code == 200
    assert init.json()["is_repository"] is True

    suite = workspace_path / "tests" / "demo.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text("*** Test Cases ***\nDemo\n    Log    hi\n", encoding="utf-8")

    # Brand-new files appear as untracked in Source Control.
    status = await client.get("/api/v1/git/status")
    assert status.status_code == 200
    changes = status.json()["changes"]
    assert any(
        item["path"].endswith("demo.robot") and item["status"] == "untracked"
        for item in changes
    )

    commit = await client.post(
        "/api/v1/git/commit",
        json={"message": "Add demo suite"},
    )
    assert commit.status_code == 200
    assert commit.json()["message"] == "Add demo suite"

    suite.write_text("*** Test Cases ***\nDemo\n    Log    updated\n", encoding="utf-8")
    dirty = await client.get("/api/v1/git/status")
    assert dirty.status_code == 200
    assert len(dirty.json()["changes"]) >= 1

    history = await client.get("/api/v1/git/history")
    assert history.status_code == 200
    assert len(history.json()) >= 1

    detail = await client.get(f"/api/v1/git/history/{history.json()[0]['hash']}")
    assert detail.status_code == 200
    assert detail.json()["message"] == "Add demo suite"

    diff = await client.get("/api/v1/git/diff", params={"file": str(suite)})
    assert diff.status_code == 200


@pytest.mark.asyncio
async def test_git_branch_checkout(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    workspace_path = Path(ws.json()["path"])
    await client.post("/api/v1/git/init")
    _git(workspace_path, "config", "user.email", "dev@example.com")
    _git(workspace_path, "config", "user.name", "Dev")

    created = await client.post(
        "/api/v1/git/create-branch",
        json={"name": "feature/login"},
    )
    assert created.status_code == 200

    branches = await client.get("/api/v1/git/branches")
    assert branches.status_code == 200
    assert any(item["name"] == "feature/login" for item in branches.json())

    checkout = await client.post(
        "/api/v1/git/checkout",
        json={"branch": "feature/login"},
    )
    assert checkout.status_code == 200
    assert checkout.json()["branch"] == "feature/login"


@pytest.mark.asyncio
async def test_health_unchanged(api_client) -> None:
    client, _fresh, _tmp_path = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert "workspace" in body["modules"]
    assert "git" not in body["modules"]
