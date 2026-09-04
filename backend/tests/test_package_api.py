"""HTTP integration tests for package endpoints."""

import sys
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

    # Avoid live PyPI in CI/integration; keep PipInstaller real.
    from robot_studio.application.services.package_service import PackageService
    from robot_studio.domain.interfaces.plugins import Capability

    class FakeRegistry:
        async def search(self, query: str) -> list[dict]:
            return [
                {
                    "name": "six",
                    "latest_version": "1.16.0",
                    "summary": f"Match {query}",
                },
            ]

        async def get_latest_version(self, name: str) -> str | None:
            return "1.16.0"

        async def get_metadata(self, name: str) -> dict | None:
            return {
                "name": name,
                "latest_version": "1.16.0",
                "summary": "Python 2 and 3 compatibility utilities",
                "author": "Benjamin Peterson",
                "homepage": "https://example.com/six",
                "license": "MIT",
                "requires": [],
            }

        async def list_versions(self, name: str) -> list[str]:
            return ["1.16.0", "1.15.0", "1.14.0"]

    fake = FakeRegistry()
    fresh.plugin_host.register(
        Capability.PACKAGE_REGISTRY,
        "pypi-registry",
        factory=lambda: fake,
    )
    assert fresh.workspace_context is not None
    fresh.package_service = PackageService(
        context=fresh.workspace_context,
        event_bus=fresh.event_bus,
        installer=fresh.plugin_host.get(Capability.INSTALLER),
        registry=fake,
    )

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
async def test_package_api_flow(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()

    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code == 201

    env = await client.post(
        "/api/v1/environments",
        json={
            "name": "pkg-env",
            "python_interpreter": sys.executable,
            "install_robot_framework": False,
        },
    )
    assert env.status_code == 201, env.text

    listed_empty = await client.get("/api/v1/packages")
    assert listed_empty.status_code == 200
    assert listed_empty.json()["robot_framework_installed"] is False

    searched = await client.get("/api/v1/packages/search", params={"q": "six"})
    assert searched.status_code == 200
    assert searched.json()["results"][0]["name"] == "six"

    versions = await client.get("/api/v1/packages/six/versions")
    assert versions.status_code == 200
    body = versions.json()
    assert body["latest_version"] == "1.16.0"
    assert body["versions"][0] == "1.16.0"
    assert "1.15.0" in body["versions"]

    installed = await client.post(
        "/api/v1/packages/install",
        json={"name": "six", "version": "1.16.0"},
    )
    assert installed.status_code == 200, installed.text
    assert installed.json()["package"]["name"].lower() == "six"
    assert isinstance(installed.json()["logs"], list)

    missing_requirements = await client.post(
        "/api/v1/packages/install-requirements",
        json={"path": str(tmp_path / "missing-requirements.txt")},
    )
    assert missing_requirements.status_code == 400
    assert "not found" in missing_requirements.json()["detail"].lower()

    export_bad = await client.post(
        "/api/v1/packages/export-requirements",
        json={"path": str(tmp_path / "requirements.json")},
    )
    assert export_bad.status_code == 400
    assert "txt" in export_bad.json()["detail"].lower()

    export_path = tmp_path / "exported-requirements.txt"
    exported = await client.post(
        "/api/v1/packages/export-requirements",
        json={"path": str(export_path)},
    )
    assert exported.status_code == 200, exported.text
    assert export_path.is_file()
    assert export_path.stat().st_size > 0
    assert any("Wrote" in line for line in exported.json()["logs"])

    listed = await client.get("/api/v1/packages")
    assert listed.status_code == 200
    names = {item["name"].lower() for item in listed.json()["packages"]}
    assert "six" in names

    detail = await client.get("/api/v1/packages/six")
    assert detail.status_code == 200
    assert detail.json()["homepage"]

    updated = await client.post(
        "/api/v1/packages/update",
        json={"name": "six"},
    )
    assert updated.status_code == 200

    blocked = await client.post(
        "/api/v1/packages/uninstall",
        json={"name": "pip"},
    )
    assert blocked.status_code == 400

    removed = await client.post(
        "/api/v1/packages/uninstall",
        json={"name": "six"},
    )
    assert removed.status_code == 200


@pytest.mark.asyncio
async def test_health_still_ok(api_client) -> None:
    client, _fresh, _tmp = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
