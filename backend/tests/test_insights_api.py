"""HTTP integration tests for project insights."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.domain.models import ExecutionRun, ExecutionStatus, IndexedSymbol
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


async def _open_workspace(client: AsyncClient, tmp_path: Path) -> Path:
    location = tmp_path / "homes"
    location.mkdir(exist_ok=True)
    response = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert response.status_code == 201
    return Path(response.json()["path"])


@pytest.mark.asyncio
async def test_insights_requires_workspace(api_client) -> None:
    client, _fresh, _tmp = api_client
    response = await client.get("/api/v1/insights")
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_insights_composition_and_run_aggregates(api_client) -> None:
    client, fresh, tmp_path = api_client
    await _open_workspace(client, tmp_path)
    workspace = fresh.workspace_context.workspace
    assert workspace is not None
    assert fresh.index_store is not None
    assert fresh.execution_repository is not None

    # Wait out the open-triggered background rebuild so it cannot wipe the
    # manual upserts below (common on slower Windows VMs).
    rebuilt = await client.post("/api/v1/index/rebuild?wait=true")
    assert rebuilt.status_code == 200, rebuilt.text

    suite = str(tmp_path / "homes" / "demo.robot")
    await fresh.index_store.upsert_symbols(
        [
            IndexedSymbol(
                id="kw1",
                name="Login",
                kind="keyword",
                file_path=Path(suite),
                line=10,
                workspace_id=workspace.id,
            ),
            IndexedSymbol(
                id="tc1",
                name="User Can Login",
                kind="test_case",
                file_path=Path(suite),
                line=20,
                workspace_id=workspace.id,
            ),
            IndexedSymbol(
                id="var1",
                name="${URL}",
                kind="variable",
                file_path=Path(suite),
                line=5,
                workspace_id=workspace.id,
            ),
        ]
    )

    now = datetime.now(UTC)
    project_id = uuid4()
    env_id = uuid4()
    for status, failed, offset in (
        (ExecutionStatus.FINISHED, 0, 0),
        (ExecutionStatus.FAILED, 1, 1),
        (ExecutionStatus.CANCELLED, 0, 2),
        (ExecutionStatus.ABORTED, 0, 3),
    ):
        await fresh.execution_repository.create(
            ExecutionRun(
                id=uuid4(),
                workspace_id=workspace.id,
                project_id=project_id,
                environment_id=env_id,
                project_name="Demo",
                suite=suite,
                status=status,
                started_at=now - timedelta(minutes=offset),
                finished_at=now - timedelta(minutes=offset),
                duration_ms=1000 + offset,
                exit_code=1 if status == ExecutionStatus.FAILED else 0,
                failed=failed,
                passed=0 if failed else 2,
                skipped=1 if status == ExecutionStatus.FINISHED else 0,
            )
        )

    response = await client.get("/api/v1/insights")
    assert response.status_code == 200
    body = response.json()
    assert body["composition"]["keyword"] == 1
    assert body["composition"]["test_case"] == 1
    assert body["composition"]["variable"] == 1
    assert len(body["composition_files"]) == 1
    assert body["composition_files"][0]["counts"]["keyword"] == 1

    runs = body["runs"]
    assert runs["total"] == 4
    assert runs["passed"] == 1
    assert runs["failed"] == 1
    assert runs["cancelled"] == 1
    assert runs["aborted"] == 1
    assert runs["skipped_tests"] == 1
    assert runs["pass_rate"] == 25.0

    assert len(body["recent_runs"]) == 4
    assert body["run_files"][0]["runs"] == 4
    assert body["run_files"][0]["failed"] == 1
    assert body["run_files"][0]["last_run_id"]
    assert body["run_files"][0]["last_failed_run_id"]


@pytest.mark.asyncio
async def test_insights_skips_project_run_labels(api_client) -> None:
    client, fresh, tmp_path = api_client
    await _open_workspace(client, tmp_path)
    workspace = fresh.workspace_context.workspace
    assert workspace is not None
    assert fresh.execution_repository is not None

    suite = str(tmp_path / "homes" / "demo.robot")
    await fresh.index_store.upsert_symbols(
        [
            IndexedSymbol(
                id="kw1",
                name="Login",
                kind="keyword",
                file_path=Path(suite),
                line=10,
                workspace_id=workspace.id,
            ),
        ]
    )
    now = datetime.now(UTC)
    await fresh.execution_repository.create(
        ExecutionRun(
            id=uuid4(),
            workspace_id=workspace.id,
            project_id=uuid4(),
            environment_id=uuid4(),
            project_name="OrangeHRM",
            suite="Project: OrangeHRM",
            status=ExecutionStatus.FINISHED,
            started_at=now,
            finished_at=now,
            duration_ms=500,
            exit_code=0,
            passed=2,
            failed=0,
        )
    )
    await fresh.execution_repository.create(
        ExecutionRun(
            id=uuid4(),
            workspace_id=workspace.id,
            project_id=uuid4(),
            environment_id=uuid4(),
            project_name="OrangeHRM",
            suite=suite,
            status=ExecutionStatus.FINISHED,
            started_at=now,
            finished_at=now,
            duration_ms=400,
            exit_code=0,
            passed=1,
            failed=0,
        )
    )

    body = (await client.get("/api/v1/insights")).json()
    assert body["runs"]["total"] == 2
    paths = [item["file_path"] for item in body["run_files"]]
    assert "Project: OrangeHRM" not in paths
    assert any(p.endswith("demo.robot") for p in paths)
    # Sole .robot file absorbs the Project: run as well as the file run.
    demo = next(
        item
        for item in body["run_files"]
        if item["file_path"].endswith("demo.robot")
    )
    assert demo["runs"] == 2
    assert body["composition"]["file"] == 1
    assert body["composition"]["test_suite"] == 1
