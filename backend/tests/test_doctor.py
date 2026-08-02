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
            Resource    ../resources/missing.resource

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
    rebuilt = await client.post("/api/v1/index/rebuild")
    assert rebuilt.status_code == 200, rebuilt.text
    analysis = await client.post("/api/v1/analysis/rebuild")
    assert analysis.status_code == 200, analysis.text
    return project.json()["id"]


@pytest.mark.asyncio
async def test_doctor_profiles(api_client) -> None:
    client, _fresh, _tmp = api_client
    res = await client.get("/api/v1/doctor/profiles")
    assert res.status_code == 200
    body = res.json()
    ids = {p["id"] for p in body["profiles"]}
    assert ids == {"quick", "default", "full"}
    provider_ids = {p["id"] for p in body["providers"]}
    assert "unused_keyword" in provider_ids
    assert "flaky_test" in provider_ids
    assert "never_executed_keyword" in provider_ids


@pytest.mark.asyncio
async def test_doctor_run_quick_and_history(api_client) -> None:
    client, _fresh, tmp_path = api_client
    await _seed_project(client, tmp_path)

    run1 = await client.post("/api/v1/doctor/run", json={"profile": "quick"})
    assert run1.status_code == 200, run1.text
    report = run1.json()
    assert report["profile"] == "quick"
    assert "summary" in report
    assert "grouped" in report
    assert "top_recommendations" in report
    assert report["graph_version"]
    assert report["execution_snapshot"] is not None
    messages = [f["message"] for f in report["findings"]]
    assert any("Unresolved import" in m or "missing.resource" in m for m in messages)
    for finding in report["findings"]:
        assert "supports_fix" in finding
        assert "rationale" in finding
        assert finding.get("category")

    report_id = report["id"]
    fetched = await client.get(f"/api/v1/doctor/report/{report_id}")
    assert fetched.status_code == 200
    assert fetched.json()["id"] == report_id

    run2 = await client.post("/api/v1/doctor/run", json={"profile": "default"})
    assert run2.status_code == 200, run2.text
    summary = run2.json()["summary"]
    assert summary["improvement_trend"] is not None
    assert summary["improvement_trend"]["previous_report_id"] == report_id
    assert isinstance(summary["total_findings"], int)
    assert isinstance(summary["critical_issues"], int)
    assert "by_severity" in summary
    assert "by_category" in summary

    history = await client.get("/api/v1/doctor/history")
    assert history.status_code == 200
    assert len(history.json()["items"]) >= 2


@pytest.mark.asyncio
async def test_doctor_full_includes_execution_providers(api_client) -> None:
    client, _fresh, tmp_path = api_client
    await _seed_project(client, tmp_path)

    res = await client.post("/api/v1/doctor/run", json={"profile": "full"})
    assert res.status_code == 200, res.text
    providers = set(res.json()["providers_run"])
    assert "flaky_test" in providers
    assert "slow_keyword" in providers
    assert "never_executed_keyword" in providers
    never = [
        f
        for f in res.json()["findings"]
        if f["inspection_id"] == "never_executed_keyword"
    ]
    assert never == []


@pytest.mark.asyncio
async def test_doctor_unknown_provider(api_client) -> None:
    client, _fresh, tmp_path = api_client
    await _seed_project(client, tmp_path)
    res = await client.post(
        "/api/v1/doctor/run",
        json={"profile": "quick", "provider_ids": ["not_a_provider"]},
    )
    assert res.status_code == 400


@pytest.mark.asyncio
async def test_doctor_report_not_found(api_client) -> None:
    client, _fresh, _tmp = api_client
    res = await client.get(f"/api/v1/doctor/report/{UUID(int=0)}")
    assert res.status_code == 404
