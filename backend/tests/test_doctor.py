"""Tests for Robot Doctor (FindingProviders + /doctor/*)."""

from __future__ import annotations

import textwrap
from pathlib import Path
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient
from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.main import create_app


def _write_suite(project_path: Path) -> None:
    resource = project_path / "resources" / "common.resource"
    resource.parent.mkdir(parents=True, exist_ok=True)
    resource.write_text(
        textwrap.dedent(
            """\
            *** Keywords ***
            Login User
                Log    login

            Dead Keyword
                No Operation
            """,
        ),
        encoding="utf-8",
    )
    suite = project_path / "tests" / "login.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        textwrap.dedent(
            """\
            *** Settings ***
            Resource    ../resources/common.resource

            *** Test Cases ***
            Can Login
                Login User
                Log    done
            """,
        ),
        encoding="utf-8",
    )


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


async def _seed_project(client: AsyncClient, tmp_path: Path) -> str:
    location = tmp_path / "homes"
    location.mkdir(exist_ok=True)
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code in (200, 201), ws.text
    project = await client.post("/api/v1/projects", json={"name": "Demo"})
    assert project.status_code in (200, 201), project.text
    project_path = Path(project.json()["path"])
    _write_suite(project_path)
    rebuilt = await client.post("/api/v1/index/rebuild?wait=true")
    assert rebuilt.status_code == 200, rebuilt.text
    analysis = await client.post("/api/v1/analysis/rebuild")
    assert analysis.status_code == 200, analysis.text
    return project.json()["id"]


@pytest.mark.asyncio
async def test_doctor_profiles_structural_only(api_client) -> None:
    client, _fresh, _tmp = api_client
    res = await client.get("/api/v1/doctor/profiles")
    assert res.status_code == 200
    body = res.json()
    ids = {p["id"] for p in body["profiles"]}
    assert ids == {"default"}
    provider_ids = {p["id"] for p in body["providers"]}
    assert provider_ids == {
        "circular_dependency",
        "duplicate_keyword",
        "unused_keyword",
        "unused_resource",
    }
    assert "missing_import" not in provider_ids
    assert "flaky_test" not in provider_ids
    assert "large_keyword" not in provider_ids


@pytest.mark.asyncio
async def test_doctor_run_and_history(api_client) -> None:
    client, _fresh, tmp_path = api_client
    await _seed_project(client, tmp_path)

    run1 = await client.post("/api/v1/doctor/run", json={"profile": "default"})
    assert run1.status_code == 200, run1.text
    report = run1.json()
    assert report["profile"] == "default"
    assert "summary" in report
    assert "grouped" in report
    assert "top_recommendations" in report
    assert report["graph_version"]
    providers = set(report["providers_run"])
    assert providers == {
        "circular_dependency",
        "duplicate_keyword",
        "unused_keyword",
        "unused_resource",
    }
    assert "missing_import" not in providers
    messages = [f["message"] for f in report["findings"]]
    assert any("Potentially unused" in m for m in messages)
    for finding in report["findings"]:
        assert finding.get("supports_fix") is False
        assert finding.get("fix_id") is None
        assert finding.get("rationale")
        assert finding.get("category")

    report_id = report["id"]
    fetched = await client.get(f"/api/v1/doctor/report/{report_id}")
    assert fetched.status_code == 200
    assert fetched.json()["id"] == report_id

    # Legacy profile aliases still run the structural set.
    run_quick = await client.post("/api/v1/doctor/run", json={"profile": "quick"})
    assert run_quick.status_code == 200, run_quick.text
    assert set(run_quick.json()["providers_run"]) == providers

    run2 = await client.post("/api/v1/doctor/run", json={"profile": "full"})
    assert run2.status_code == 200, run2.text
    assert "flaky_test" not in run2.json()["providers_run"]
    summary = run2.json()["summary"]
    assert summary["improvement_trend"] is not None
    assert summary["improvement_trend"]["previous_report_id"] == run_quick.json()["id"]

    history = await client.get("/api/v1/doctor/history")
    assert history.status_code == 200
    assert len(history.json()["items"]) >= 2


@pytest.mark.asyncio
async def test_doctor_unknown_provider(api_client) -> None:
    client, _fresh, tmp_path = api_client
    await _seed_project(client, tmp_path)
    res = await client.post(
        "/api/v1/doctor/run",
        json={"profile": "default", "provider_ids": ["not_a_provider"]},
    )
    assert res.status_code == 400


@pytest.mark.asyncio
async def test_doctor_report_not_found(api_client) -> None:
    client, _fresh, _tmp = api_client
    res = await client.get(f"/api/v1/doctor/report/{UUID(int=0)}")
    assert res.status_code == 404


@pytest.mark.asyncio
async def test_doctor_rescan_drops_findings_for_deleted_file(api_client) -> None:
    client, _fresh, tmp_path = api_client
    await _seed_project(client, tmp_path)

    run1 = await client.post("/api/v1/doctor/run", json={"profile": "default"})
    assert run1.status_code == 200, run1.text
    before = run1.json()
    unused = [
        f
        for f in before["findings"]
        if f["inspection_id"] == "unused_keyword"
        and "Dead Keyword" in f["message"]
    ]
    assert unused, before["findings"]
    deleted_path = unused[0]["file_path"]

    deleted = await client.post("/api/v1/files/delete", json={"path": deleted_path})
    assert deleted.status_code == 200, deleted.text

    # Wait for watcher debounce + analysis rebind after file removal.
    import asyncio

    for _ in range(40):
        run2 = await client.post("/api/v1/doctor/run", json={"profile": "default"})
        assert run2.status_code == 200, run2.text
        messages = [f["message"] for f in run2.json()["findings"]]
        if not any("Dead Keyword" in m for m in messages):
            break
        await asyncio.sleep(0.05)
    else:
        pytest.fail(f"Doctor still reports deleted file: {run2.json()['findings']}")

    assert run2.json()["summary"]["total_findings"] < before["summary"]["total_findings"]
