"""Persistence + HTTP tests for run configurations."""

import sys
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient
from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.infrastructure.run_configuration.store import load_store, store_path
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


async def _open_project(
    client: AsyncClient,
    tmp_path: Path,
    *,
    install_robot: bool = False,
) -> dict:
    location = tmp_path / "homes"
    location.mkdir(exist_ok=True)
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
            "install_robot_framework": install_robot,
        },
    )
    assert env.status_code == 201, env.text
    project = await client.post("/api/v1/projects", json={"name": "Demo"})
    assert project.status_code == 201
    return {"project": project.json(), "env": env.json()}


@pytest.mark.asyncio
async def test_run_configuration_crud_persists_on_disk(api_client) -> None:
    client, _fresh, tmp_path = api_client
    opened = await _open_project(client, tmp_path)
    env_id = opened["env"]["id"]
    project_path = Path(opened["project"]["path"])

    empty = await client.get("/api/v1/run-configurations")
    assert empty.status_code == 200
    assert empty.json()["configurations"] == []
    assert empty.json()["active_id"] is None

    created = await client.post(
        "/api/v1/run-configurations",
        json={
            "name": "Smoke - Staging",
            "environment_id": env_id,
            "include_tags": ["smoke"],
            "exclude_tags": ["wip"],
            "variables": [
                {"key": "ENV", "value": "staging"},
                {"key": "BROWSER", "value": "chrome"},
            ],
            "variable_files": ["config/staging.py"],
            "extra_robot_args": ["--loglevel", "DEBUG"],
        },
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["name"] == "Smoke - Staging"
    assert body["include_tags"] == ["smoke"]
    assert body["exclude_tags"] == ["wip"]
    config_id = body["id"]

    listed = await client.get("/api/v1/run-configurations")
    assert listed.json()["active_id"] == config_id
    assert len(listed.json()["configurations"]) == 1

    store = load_store(project_path)
    assert store.active_id is not None
    assert store.configurations[0].name == "Smoke - Staging"
    assert store_path(project_path).is_file()

    duplicated = await client.post(f"/api/v1/run-configurations/{config_id}/duplicate")
    assert duplicated.status_code == 200
    assert duplicated.json()["name"] == "Smoke - Staging copy"
    assert duplicated.json()["include_tags"] == ["smoke"]
    assert duplicated.json()["id"] != config_id

    activated = await client.post(
        "/api/v1/run-configurations/activate",
        json={"configuration_id": None},
    )
    assert activated.status_code == 200
    assert activated.json()["active_id"] is None

    deleted = await client.delete(f"/api/v1/run-configurations/{config_id}")
    assert deleted.status_code == 200
    remaining = await client.get("/api/v1/run-configurations")
    names = [item["name"] for item in remaining.json()["configurations"]]
    assert names == ["Smoke - Staging copy"]


@pytest.mark.asyncio
async def test_run_file_with_configuration_builds_robot_args(api_client) -> None:
    client, fresh, tmp_path = api_client
    opened = await _open_project(client, tmp_path, install_robot=True)
    project_path = Path(opened["project"]["path"])
    suite = project_path / "tests" / "sample.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Test Cases ***\nHello\n    [Tags]    smoke\n    Log    via api\n",
        encoding="utf-8",
    )
    vars_dir = project_path / "config"
    vars_dir.mkdir()
    (vars_dir / "staging.py").write_text("ENV = 'staging'\n", encoding="utf-8")

    created = await client.post(
        "/api/v1/run-configurations",
        json={
            "name": "Smoke - Staging",
            "include_tags": ["smoke"],
            "exclude_tags": ["wip"],
            "variables": [{"key": "ENV", "value": "staging"}],
            "variable_files": ["config/staging.py"],
        },
    )
    assert created.status_code == 200, created.text
    config_id = created.json()["id"]

    started = await client.post(
        "/api/v1/execution/run",
        json={"file": str(suite), "configuration_id": config_id},
    )
    assert started.status_code == 200, started.text
    command = started.json()["command"]
    assert "--include smoke" in command
    assert "--exclude wip" in command
    assert "--variable ENV:staging" in command
    assert "--variablefile" in command
    assert started.json()["configuration_name"] == "Smoke - Staging"
    assert started.json()["configuration_id"] == config_id
    assert fresh.workspace_context.environment is not None
    assert str(fresh.workspace_context.environment.id) == opened["env"]["id"]


@pytest.mark.asyncio
async def test_run_without_configuration_unchanged(api_client) -> None:
    client, _fresh, tmp_path = api_client
    opened = await _open_project(client, tmp_path, install_robot=True)
    project_path = Path(opened["project"]["path"])
    suite = project_path / "tests" / "sample.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Test Cases ***\nHello\n    Log    via api\n",
        encoding="utf-8",
    )
    started = await client.post(
        "/api/v1/execution/run",
        json={"file": str(suite)},
    )
    assert started.status_code == 200, started.text
    command = started.json()["command"]
    assert "--include" not in command
    assert started.json()["configuration_id"] is None
    assert started.json()["configuration_name"] == ""


@pytest.mark.asyncio
async def test_rejects_studio_owned_extra_args(api_client) -> None:
    client, _fresh, tmp_path = api_client
    await _open_project(client, tmp_path)
    blocked = await client.post(
        "/api/v1/run-configurations",
        json={
            "name": "Bad",
            "extra_robot_args": ["--outputdir", "/tmp"],
        },
    )
    assert blocked.status_code == 400
