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
        try:
            yield client, fresh, tmp_path
        finally:
            await fresh.shutdown()
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
        json={"name": "Demo"},
    )
    assert created.status_code == 201
    body = created.json()
    assert body["name"] == "Demo"
    assert body["type"] == "empty"

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

    by_path = await client.post(
        "/api/v1/projects/open-path",
        json={"path": body["path"]},
    )
    assert by_path.status_code == 200
    payload = by_path.json()
    assert payload["project"]["name"] == "Demo"
    assert payload["workspace"]["name"] == "WS"


@pytest.mark.asyncio
async def test_open_project_by_path_without_active_workspace(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "data_dir", tmp_path / "data")
    settings.data_dir.mkdir(parents=True, exist_ok=True)

    setup = Container()
    await setup.initialize_async()
    app = create_app()
    app.dependency_overrides[get_gateway] = lambda: RestGateway(setup)
    transport = ASGITransport(app=app)

    location = tmp_path / "homes"
    location.mkdir()
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        ws = await client.post(
            "/api/v1/workspaces",
            json={"name": "Lonely", "location": str(location)},
        )
        assert ws.status_code == 201
        created = await client.post(
            "/api/v1/projects",
            json={"name": "Solo"},
        )
        assert created.status_code == 201
        project_path = created.json()["path"]

    await setup.shutdown()
    app.dependency_overrides.clear()

    # New process / container: no active workspace in memory.
    lonely = Container()
    await lonely.initialize_async()
    app2 = create_app()
    app2.dependency_overrides[get_gateway] = lambda: RestGateway(lonely)
    transport2 = ASGITransport(app=app2)
    async with AsyncClient(transport=transport2, base_url="http://test") as client:
        by_path = await client.post(
            "/api/v1/projects/open-path",
            json={"path": project_path},
        )
    await lonely.shutdown()
    app2.dependency_overrides.clear()

    assert by_path.status_code == 200
    assert by_path.json()["project"]["name"] == "Solo"
    assert by_path.json()["workspace"]["name"] == "Lonely"


@pytest.mark.asyncio
async def test_open_project_by_path_initializes_in_project_workspace(api_client) -> None:
    client, _fresh, tmp_path = api_client
    standalone = tmp_path / "my-robot-test-project"
    standalone.mkdir()
    (standalone / "suite.robot").write_text(
        "*** Test Cases ***\nHello\n    Log    hi\n",
        encoding="utf-8",
    )

    response = await client.post(
        "/api/v1/projects/open-path",
        json={"path": str(standalone)},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["project"]["name"] == "my-robot-test-project"
    assert body["project"]["path"] == str(standalone.resolve())
    assert body["workspace"]["path"] == str(standalone.resolve())
    assert body["workspace"]["id"] == body["project"]["id"]
    assert (standalone / ".robotstudio" / "workspace.json").is_file()
    assert not (standalone / "Projects").exists()
    assert body["needs_environment"] is True

    # Second open reuses the same in-project workspace / project.
    again = await client.post(
        "/api/v1/projects/open-path",
        json={"path": str(standalone)},
    )
    assert again.status_code == 200, again.text
    assert again.json()["project"]["id"] == body["project"]["id"]
    assert again.json()["workspace"]["id"] == body["workspace"]["id"]
    assert again.json()["workspace"]["path"] == str(standalone.resolve())


@pytest.mark.asyncio
async def test_open_project_detects_existing_venv(api_client) -> None:
    client, _fresh, tmp_path = api_client
    standalone = tmp_path / "with-venv"
    standalone.mkdir()
    (standalone / "suite.robot").write_text(
        "*** Test Cases ***\nHello\n    Log    hi\n",
        encoding="utf-8",
    )
    venv = standalone / ".venv"
    venv.mkdir()
    (venv / "pyvenv.cfg").write_text("home = /usr\n", encoding="utf-8")

    response = await client.post(
        "/api/v1/projects/open-path",
        json={"path": str(standalone)},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["needs_environment"] is True
    assert any(item["path"] == str(venv.resolve()) for item in body["detected_environments"])


@pytest.mark.asyncio
async def test_create_standalone_project(api_client) -> None:
    client, _fresh, tmp_path = api_client
    parent = tmp_path / "homes"
    parent.mkdir()

    response = await client.post(
        "/api/v1/projects/standalone",
        json={"name": "Fresh", "location": str(parent)},
    )
    assert response.status_code == 201, response.text
    body = response.json()
    project_path = Path(body["project"]["path"])
    assert project_path == parent / "Fresh"
    assert body["workspace"]["path"] == str(project_path.resolve())
    assert body["workspace"]["id"] == body["project"]["id"]
    assert (project_path / ".robotstudio" / "workspace.json").is_file()
    assert not (project_path / "Projects").exists()
    gitignore = (project_path / ".gitignore").read_text(encoding="utf-8")
    assert ".robotstudio/" in gitignore
    assert "Environments/" not in gitignore
    assert "Reports/" not in gitignore


@pytest.mark.asyncio
async def test_open_project_by_path_opens_workspace_root_with_project(
    api_client,
) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()

    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "RootWS", "location": str(location)},
    )
    assert ws.status_code == 201
    workspace_path = ws.json()["path"]

    created = await client.post(
        "/api/v1/projects",
        json={"name": "Inside"},
    )
    assert created.status_code == 201

    response = await client.post(
        "/api/v1/projects/open-path",
        json={"path": workspace_path},
    )
    assert response.status_code == 200, response.text
    assert response.json()["project"]["name"] == "Inside"
    assert response.json()["workspace"]["path"] == workspace_path


@pytest.mark.asyncio
async def test_open_project_by_path_rejects_non_robot_unless_forced(api_client) -> None:
    client, _fresh, tmp_path = api_client
    empty = tmp_path / "plain-folder"
    empty.mkdir()

    blocked = await client.post(
        "/api/v1/projects/open-path",
        json={"path": str(empty)},
    )
    assert blocked.status_code == 400, blocked.text
    assert "does not look like" in blocked.json()["detail"]

    forced = await client.post(
        "/api/v1/projects/open-path",
        json={"path": str(empty), "force": True},
    )
    assert forced.status_code == 200, forced.text
    body = forced.json()
    assert body["project"]["name"] == "plain-folder"
    assert body["workspace"]["path"] == str(empty.resolve())
    assert (empty / ".robotstudio" / "workspace.json").is_file()


@pytest.mark.asyncio
async def test_health_still_ok(api_client) -> None:
    client, _, _ = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
