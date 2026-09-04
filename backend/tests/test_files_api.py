"""API tests for file ops and document symbols."""

from __future__ import annotations

import shutil
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
async def test_files_tree_lazy_depth_zero(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "LazyWS", "location": str(location)},
    )
    assert ws.status_code == 201
    project = await client.post(
        "/api/v1/projects",
        json={"name": "LazyProj"},
    )
    assert project.status_code == 201
    project_path = Path(project.json()["path"])
    tests = project_path / "tests"
    tests.mkdir(parents=True, exist_ok=True)
    for i in range(5):
        (tests / f"suite_{i}.robot").write_text(
            "*** Test Cases ***\nA\n    Log  1\n",
            encoding="utf-8",
        )

    root = await client.get("/api/v1/files/tree", params={"depth": 0})
    assert root.status_code == 200
    entries = root.json()["entries"]
    # The Explorer is rooted at the active project, not the workspace home,
    # so the scaffold folders are the top level here.
    by_name = {item["name"]: item for item in entries}
    assert {"tests", "resources", "variables"} <= set(by_name)
    tests_entry = by_name["tests"]
    assert tests_entry["is_dir"] is True
    assert tests_entry["has_children"] is True
    # depth=0 is lazy: children are advertised but never expanded.
    assert all(item["children"] == [] for item in entries)

    tests_tree = await client.get(
        "/api/v1/files/tree",
        params={"path": str(tests), "depth": 0},
    )
    assert tests_tree.status_code == 200
    names = {item["name"] for item in tests_tree.json()["entries"]}
    assert "suite_0.robot" in names
    assert "suite_4.robot" in names
    assert all(item["children"] == [] for item in tests_tree.json()["entries"])


@pytest.mark.asyncio
async def test_save_does_not_resurrect_externally_deleted_workspace(api_client) -> None:
    """Deleting the workspace in Finder must not be undone by the next save."""
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "GoneWS", "location": str(location)},
    )
    assert ws.status_code == 201
    root = Path(ws.json()["path"])

    shutil.rmtree(root)

    written = await client.put(
        "/api/v1/files/content",
        json={"path": str(root / "tests" / "new.robot"), "content": "*** Test Cases ***\n"},
    )
    assert written.status_code == 400
    assert "no longer on disk" in written.json()["detail"]
    assert not root.exists()


@pytest.mark.asyncio
async def test_files_and_document_symbols(api_client) -> None:
    client, _fresh, tmp_path = api_client
    location = tmp_path / "homes"
    location.mkdir()
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code == 201

    project = await client.post(
        "/api/v1/projects",
        json={"name": "Demo"},
    )
    assert project.status_code == 201
    suite = Path(project.json()["path"]) / "tests" / "demo.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Keywords ***\nHello World\n    Log    hi\n",
        encoding="utf-8",
    )

    tree = await client.get("/api/v1/files/tree", params={"depth": 4})
    assert tree.status_code == 200
    # Rooted at the active project, so the suite is reachable under tests/.
    tests_entry = next(
        item for item in tree.json()["entries"] if item["name"] == "tests"
    )
    assert "demo.robot" in {child["name"] for child in tests_entry["children"]}

    content = await client.get("/api/v1/files/content", params={"path": str(suite)})
    assert content.status_code == 200
    assert "Hello World" in content.json()["content"]

    written = await client.put(
        "/api/v1/files/content",
        json={"path": str(suite), "content": "*** Keywords ***\nUpdated\n    Log    x\n"},
    )
    assert written.status_code == 200
    assert suite.read_text(encoding="utf-8").startswith("*** Keywords ***")

    rebuild = await client.post("/api/v1/index/rebuild?wait=true")
    assert rebuild.status_code == 200

    symbols = await client.get(
        "/api/v1/language/document-symbols",
        params={"file": str(suite)},
    )
    assert symbols.status_code == 200
    names = [item["name"] for item in symbols.json()["results"]]
    assert "Updated" in names

    workspace = await client.get(
        "/api/v1/language/workspace-symbols",
        params={"q": "Updated"},
    )
    assert workspace.status_code == 200
    assert any(item["name"] == "Updated" for item in workspace.json()["results"])
