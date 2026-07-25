"""Tests for plugin discovery, lifecycle, and API."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.core.events import PluginEnabled, PluginLoaded
from robot_studio.infrastructure.plugins.plugin_loader import PluginLoader
from robot_studio.infrastructure.plugins.plugin_manager import PluginManager
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


def test_plugin_loader_validates_manifest_and_entry(tmp_path: Path) -> None:
    plugin_dir = tmp_path / "sample"
    plugin_dir.mkdir()
    manifest = {
        "id": "sample",
        "name": "Sample",
        "version": "1.0.0",
        "entry": "plugin.py",
        "capabilities": ["toolbar-action"],
    }
    (plugin_dir / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")

    loader = PluginLoader()
    with pytest.raises(Exception):
        loader.load_manifest(plugin_dir / "plugin.json")

    (plugin_dir / "plugin.py").write_text(
        "class Plugin:\n    async def initialize(self, context): pass\n",
        encoding="utf-8",
    )
    loaded = loader.load_manifest(plugin_dir / "plugin.json")
    assert loaded.id == "sample"


def test_plugin_loader_skips_duplicate_ids(tmp_path: Path) -> None:
    workspace = tmp_path / "WS"
    plugins_root = workspace / "Plugins"
    for name in ("one", "two"):
        plugin_dir = plugins_root / name
        plugin_dir.mkdir(parents=True)
        (plugin_dir / "plugin.json").write_text(
            json.dumps(
                {
                    "id": "duplicate",
                    "name": name,
                    "version": "1.0.0",
                    "entry": "plugin.py",
                    "capabilities": [],
                },
            ),
            encoding="utf-8",
        )
        (plugin_dir / "plugin.py").write_text("class Plugin: pass", encoding="utf-8")

    loader = PluginLoader()
    discovered = loader.discover(workspace_path=workspace)
    assert len([item for item in discovered if item.manifest.id == "duplicate"]) == 1


@pytest.mark.asyncio
async def test_plugin_manager_loads_external_plugin(tmp_path: Path) -> None:
    workspace = tmp_path / "WS"
    plugin_dir = workspace / "Plugins" / "hello"
    plugin_dir.mkdir(parents=True)
    (plugin_dir / "plugin.json").write_text(
        json.dumps(
            {
                "id": "hello",
                "name": "Hello Plugin",
                "version": "0.1.0",
                "author": "Test",
                "description": "Demo",
                "entry": "plugin.py",
                "capabilities": ["toolbar-action"],
            },
        ),
        encoding="utf-8",
    )
    (plugin_dir / "plugin.py").write_text(
        "\n".join(
            [
                "class Plugin:",
                "    async def initialize(self, context): pass",
                "    async def activate(self, context): pass",
                "    async def deactivate(self, context): pass",
                "    async def dispose(self, context): pass",
            ],
        ),
        encoding="utf-8",
    )

    container = Container()
    container.initialize()
    assert container.plugin_manager is not None

    from datetime import UTC, datetime
    from uuid import uuid4

    from robot_studio.domain.models import Workspace

    ws = Workspace(
        id=uuid4(),
        name="WS",
        path=workspace,
        created_at=datetime.now(UTC),
    )
    await container.workspace_context.open(ws)
    await container.plugin_manager.discover_and_load()
    plugin = container.plugin_manager.get_plugin("hello")
    assert plugin is not None
    assert plugin.status in {"loaded", "enabled"}
    await container.shutdown()


@pytest.mark.asyncio
async def test_workspace_open_discovers_plugins(api_client) -> None:
    client, fresh, tmp_path = api_client
    homes = tmp_path / "homes"
    homes.mkdir(parents=True)

    created = await client.post(
        "/api/v1/workspaces",
        json={"name": "PluginWS", "location": str(homes)},
    )
    assert created.status_code == 201
    workspace_path = Path(created.json()["path"])

    plugin_dir = workspace_path / "Plugins" / "it-plugin"
    plugin_dir.mkdir(parents=True)
    (plugin_dir / "plugin.json").write_text(
        json.dumps(
            {
                "id": "it-plugin",
                "name": "Integration Test Plugin",
                "version": "0.0.1",
                "entry": "plugin.py",
                "capabilities": ["toolbar-action"],
            },
        ),
        encoding="utf-8",
    )
    (plugin_dir / "plugin.py").write_text(
        "class Plugin:\n"
        "    async def initialize(self, context): pass\n"
        "    async def activate(self, context): pass\n"
        "    async def deactivate(self, context): pass\n"
        "    async def dispose(self, context): pass\n",
        encoding="utf-8",
    )

    refreshed = await client.post("/api/v1/plugins/refresh")
    assert refreshed.status_code == 200
    plugins = refreshed.json()["plugins"]
    assert any(item["id"] == "it-plugin" for item in plugins)


@pytest.mark.asyncio
async def test_plugins_api_lists_and_actions(api_client) -> None:
    client, fresh, tmp_path = api_client
    response = await client.get("/api/v1/plugins")
    assert response.status_code == 200
    plugins = response.json()["plugins"]
    assert any(item["id"] == "pip-installer" for item in plugins)

    detail = await client.get("/api/v1/plugins/pip-installer")
    assert detail.status_code == 200
    assert detail.json()["name"] == "Pip Installer"

    reload = await client.post(
        "/api/v1/plugins/reload",
        json={"id": "pip-installer"},
    )
    assert reload.status_code == 200

    disable = await client.post(
        "/api/v1/plugins/disable",
        json={"id": "pip-installer"},
    )
    assert disable.status_code == 400


@pytest.mark.asyncio
async def test_plugin_events_publish(api_client) -> None:
    _client, fresh, _tmp = api_client
    assert fresh.plugin_manager is not None
    events: list[object] = []

    async def on_loaded(event: PluginLoaded) -> None:
        events.append(event)

    async def on_enabled(event: PluginEnabled) -> None:
        events.append(event)

    fresh.event_bus.subscribe(PluginLoaded, on_loaded)
    fresh.event_bus.subscribe(PluginEnabled, on_enabled)
    await fresh.plugin_manager.load_builtins()
    assert any(isinstance(item, PluginLoaded) for item in events)


@pytest.mark.asyncio
async def test_health_unchanged_with_plugins(api_client) -> None:
    client, _fresh, _tmp = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "keywords" in body["modules"]
