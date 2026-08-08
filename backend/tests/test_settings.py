"""Tests for SettingsService persistence, migration, and API."""

from __future__ import annotations

from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.application.services.settings_service import SettingsService
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.domain.models.app_settings import (
    AppSettings,
    migrate_settings_dict,
)
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


def test_defaults_and_persist(tmp_path: Path) -> None:
    service = SettingsService(data_dir=tmp_path)
    snap = service.load()
    assert snap.editor.font_size == 13
    assert snap.execution.large_run_threshold == 100
    assert snap.appearance.restore_last_project is True
    assert snap.appearance.accent == "teal"
    assert Path(tmp_path / "settings.json").is_file()


@pytest.mark.asyncio
async def test_update_merges_and_survives_reload(tmp_path: Path) -> None:
    service = SettingsService(data_dir=tmp_path)
    service.load()
    updated = await service.update(
        {
            "editor": {"word_wrap": False, "font_size": 16},
            "execution": {"large_run_threshold": 5},
            "appearance": {
                "theme": "system",
                "accent": "blue",
                "restore_last_project": False,
            },
        },
    )
    assert updated.editor.word_wrap is False
    assert updated.editor.font_size == 16
    assert updated.editor.font_family == "Menlo"
    assert updated.execution.large_run_threshold == 5
    assert updated.appearance.theme == "system"
    assert updated.appearance.accent == "blue"
    assert updated.appearance.restore_last_project is False

    reloaded = SettingsService(data_dir=tmp_path).load()
    assert reloaded.editor.font_size == 16
    assert reloaded.execution.large_run_threshold == 5
    assert reloaded.appearance.accent == "blue"
    assert reloaded.appearance.restore_last_project is False


def test_migrate_legacy_flat_keys() -> None:
    migrated = migrate_settings_dict(
        {
            "version": 0,
            "large_run_threshold": 42,
            "content_search_extensions": ".robot,.py",
            "word_wrap": False,
            "theme": "light",
        },
    )
    assert migrated["version"] == 1
    assert migrated["execution"]["large_run_threshold"] == 42
    assert ".robot" in migrated["search"]["content_search_extensions"]
    assert migrated["editor"]["word_wrap"] is False
    assert migrated["appearance"]["theme"] == "light"


@pytest.mark.asyncio
async def test_settings_api(api_client) -> None:
    client, _, _ = api_client
    current = await client.get("/api/v1/settings")
    assert current.status_code == 200
    body = current.json()
    assert "editor" in body
    assert "execution" in body

    patched = await client.patch(
        "/api/v1/settings",
        json={
            "editor": {"auto_save": True, "tab_width": 2},
            "search": {"ignore_patterns": [".git", "build"]},
        },
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["editor"]["auto_save"] is True
    assert patched.json()["editor"]["tab_width"] == 2
    assert "build" in patched.json()["search"]["ignore_patterns"]

    again = await client.get("/api/v1/settings")
    assert again.json()["editor"]["auto_save"] is True
    assert again.json()["appearance"]["accent"] == "teal"

    reset = await client.post("/api/v1/settings/reset")
    assert reset.status_code == 200
    assert reset.json()["editor"]["auto_save"] is False
    assert reset.json()["appearance"]["accent"] == "teal"
    assert AppSettings.from_api(reset.json()).editor.tab_width == 4


def test_invalid_accent_falls_back_to_teal() -> None:
    from robot_studio.domain.models.app_settings import AppearanceSettings

    assert AppearanceSettings.from_api({"accent": "purple"}).accent == "teal"
    assert AppearanceSettings.from_api({"accent": "BLUE"}).accent == "blue"
