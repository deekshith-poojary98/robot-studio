"""HTTP integration tests for Test Explorer endpoints."""

from __future__ import annotations

import asyncio
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

    app = create_app()
    app.dependency_overrides[get_gateway] = lambda: RestGateway(fresh)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        try:
            yield client, fresh, tmp_path
        finally:
            await fresh.shutdown()
    app.dependency_overrides.clear()


async def _seed_workspace(client: AsyncClient, tmp_path: Path) -> dict:
    location = tmp_path / "homes"
    location.mkdir(exist_ok=True)
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "TE", "location": str(location)},
    )
    assert ws.status_code == 201, ws.text

    env = await client.post(
        "/api/v1/environments",
        json={
            "name": "te-env",
            "python_interpreter": sys.executable,
            "install_robot_framework": True,
        },
    )
    assert env.status_code == 201, env.text

    project = await client.post(
        "/api/v1/projects",
        json={"name": "SuiteProj"},
    )
    assert project.status_code == 201, project.text
    project_path = Path(project.json()["path"])
    suite = project_path / "tests" / "demo.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Settings ***\n"
        "Suite Setup    Log    boot\n"
        "Test Tags    smoke\n"
        "\n"
        "*** Test Cases ***\n"
        "Alpha\n"
        "    [Tags]    ui\n"
        "    Log    a\n"
        "\n"
        "Beta\n"
        "    Fail    boom\n",
        encoding="utf-8",
    )
    tasks = project_path / "tests" / "tasks.robot"
    tasks.write_text(
        "*** Tasks ***\n"
        "Nightly\n"
        "    Log    task\n",
        encoding="utf-8",
    )

    # Trigger index rebuild for discovery.
    rebuild = await client.post("/api/v1/index/rebuild")
    assert rebuild.status_code == 200, rebuild.text
    await asyncio.sleep(0.3)

    return {
        "workspace": ws.json(),
        "project": project.json(),
        "suite": str(suite),
    }


async def _wait_status(
    client: AsyncClient,
    *,
    run_id: str | None = None,
    timeout: float = 90.0,
) -> dict:
    deadline = asyncio.get_event_loop().time() + timeout
    seen_active = run_id is None
    while asyncio.get_event_loop().time() < deadline:
        response = await client.get("/api/v1/execution/status")
        assert response.status_code == 200
        body = response.json()
        current = body.get("run") or {}
        current_id = current.get("id")
        if run_id is not None:
            if current_id == run_id and body["status"] in {
                "starting",
                "running",
                "stopping",
            }:
                seen_active = True
            if (
                seen_active
                and current_id == run_id
                and body["status"] in {"finished", "failed", "cancelled"}
            ):
                return body
        elif body["status"] in {"finished", "failed", "cancelled"}:
            return body
        await asyncio.sleep(0.2)
    raise TimeoutError("execution status wait timed out")


@pytest.mark.asyncio
async def test_health_unchanged_with_tests_module(api_client) -> None:
    client, _, _ = api_client
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "version" in body


@pytest.mark.asyncio
async def test_discovery_and_filtering(api_client) -> None:
    client, _, tmp_path = api_client
    seeded = await _seed_workspace(client, tmp_path)

    lazy_tree = await client.get("/api/v1/tests/tree", params={"lazy": "true"})
    assert lazy_tree.status_code == 200, lazy_tree.text
    lazy_root = lazy_tree.json()["tree"]
    lazy_suite = lazy_root["children"][0]["children"][0]
    assert lazy_suite["kind"] == "suite"
    assert lazy_suite["detail"] == "expand"
    assert lazy_suite["children"] == []

    count = await client.get("/api/v1/tests/count", params={"project_wide": "true"})
    assert count.status_code == 200
    assert count.json()["count"] >= 2

    tree = await client.get("/api/v1/tests/tree", params={"lazy": "false"})
    assert tree.status_code == 200, tree.text
    root = tree.json()["tree"]
    assert root["kind"] == "workspace"
    assert root["children"]
    project = root["children"][0]
    assert project["kind"] == "project"
    assert project["children"], "expected suite nodes"
    suite = project["children"][0]
    assert suite["kind"] == "suite"
    all_children = [
        child
        for suite_node in project["children"]
        for child in suite_node["children"]
    ]
    kinds = {child["kind"] for child in all_children}
    names = {child["name"] for child in all_children}
    assert "test" in kinds
    assert "task" in kinds or "Nightly" in names
    assert "Alpha" in names
    assert "Beta" in names

    file_nodes = await client.get(
        "/api/v1/tests/file",
        params={"path": seeded["suite"]},
    )
    assert file_nodes.status_code == 200, file_nodes.text
    names = {item["name"] for item in file_nodes.json()["nodes"]}
    assert "Alpha" in names
    assert "Beta" in names

    filtered = await client.get("/api/v1/tests/tree", params={"q": "alpha"})
    assert filtered.status_code == 200
    blob = filtered.text.lower()
    assert "alpha" in blob

    tagged = await client.get("/api/v1/tests/tree", params={"q": "smoke"})
    assert tagged.status_code == 200
    assert "smoke" in tagged.text.lower() or "alpha" in tagged.text.lower()


@pytest.mark.asyncio
async def test_incremental_refresh_after_file_change(api_client) -> None:
    client, _, tmp_path = api_client
    seeded = await _seed_workspace(client, tmp_path)
    suite = Path(seeded["suite"])

    before = await client.get("/api/v1/tests/file", params={"path": str(suite)})
    assert before.status_code == 200
    assert "Gamma" not in before.text

    suite.write_text(
        suite.read_text(encoding="utf-8")
        + "\nGamma\n    Log    g\n",
        encoding="utf-8",
    )
    rebuild = await client.post("/api/v1/index/rebuild")
    assert rebuild.status_code == 200
    await asyncio.sleep(0.4)

    after = await client.get("/api/v1/tests/file", params={"path": str(suite)})
    assert after.status_code == 200
    assert "Gamma" in after.text


@pytest.mark.asyncio
async def test_run_test_suite_tag_and_failed(api_client) -> None:
    client, _, tmp_path = api_client
    seeded = await _seed_workspace(client, tmp_path)
    suite = seeded["suite"]

    run_test = await client.post(
        "/api/v1/tests/run",
        json={"file": suite, "name": "Alpha"},
    )
    assert run_test.status_code == 200, run_test.text
    assert "Alpha" in run_test.json()["suite"]
    await _wait_status(client, run_id=run_test.json()["id"])

    run_suite = await client.post(
        "/api/v1/tests/run-suite",
        json={"file": suite},
    )
    assert run_suite.status_code == 200, run_suite.text
    await _wait_status(client, run_id=run_suite.json()["id"])

    run_tag = await client.post(
        "/api/v1/tests/run-tag",
        json={"tag": "smoke"},
    )
    assert run_tag.status_code == 200, run_tag.text
    assert "smoke" in run_tag.json()["suite"].lower()
    await _wait_status(client, run_id=run_tag.json()["id"])

    # Ensure a failure exists then re-run failed.
    fail_run = await client.post(
        "/api/v1/tests/run",
        json={"file": suite, "name": "Beta"},
    )
    assert fail_run.status_code == 200, fail_run.text
    await _wait_status(client, run_id=fail_run.json()["id"])

    run_failed = await client.post("/api/v1/tests/run-failed")
    assert run_failed.status_code == 200, run_failed.text
    assert "Failed" in run_failed.json()["suite"]
    await _wait_status(client, run_id=run_failed.json()["id"])

    selected = await client.post(
        "/api/v1/tests/run-selected",
        json={"tests": [{"file": suite, "name": "Alpha"}]},
    )
    assert selected.status_code == 200, selected.text
    await _wait_status(client, run_id=selected.json()["id"])


@pytest.mark.asyncio
async def test_large_run_requires_confirmation(api_client, monkeypatch: pytest.MonkeyPatch) -> None:
    client, _, tmp_path = api_client
    monkeypatch.setattr(settings, "large_run_threshold", 2)
    await _seed_workspace(client, tmp_path)

    # Suite-wide / project run without confirm → 409 when over threshold.
    blocked = await client.post("/api/v1/tests/run-suite", json={})
    assert blocked.status_code == 409, blocked.text
    detail = blocked.json()["detail"]
    assert detail["code"] == "large_run_confirmation_required"
    assert detail["count"] >= 2
    assert detail["threshold"] == 2

    project_blocked = await client.post("/api/v1/execution/run-project", json={})
    assert project_blocked.status_code == 409, project_blocked.text
    assert project_blocked.json()["detail"]["code"] == "large_run_confirmation_required"

    # Tag include can also exceed threshold (smoke covers Alpha via suite tags).
    tag_blocked = await client.post("/api/v1/tests/run-tag", json={"tag": "smoke"})
    # May be under or over depending on discovery; force with wildcard which always confirms.
    wild = await client.post("/api/v1/tests/run-tag", json={"tag": "smoke*"})
    assert wild.status_code == 409, wild.text
    assert wild.json()["detail"]["code"] == "large_run_confirmation_required"

    confirmed = await client.post(
        "/api/v1/tests/run-suite",
        json={"confirm": True},
    )
    assert confirmed.status_code == 200, confirmed.text
    assert confirmed.json()["id"]
    # Stop promptly so the suite stays fast.
    await client.post("/api/v1/execution/stop")
