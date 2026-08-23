"""Unit + API tests for Analysis Engine + Inspection Engine."""

from __future__ import annotations

from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.infrastructure.analysis.normalize import (
    normalize_keyword_name,
    normalize_variable_name,
)
from robot_studio.infrastructure.analysis.semantic_extractor import extract_file_semantics
from robot_studio.main import create_app


def test_normalize_keyword_and_variable() -> None:
    assert normalize_keyword_name("Hello World") == "helloworld"
    assert normalize_keyword_name("Hello_World") == "helloworld"
    assert normalize_variable_name("${BASE_URL}") == "baseurl"
    assert normalize_variable_name("${obj.attr}") == "obj"


def test_extract_file_semantics_calls_and_imports(tmp_path: Path) -> None:
    resource = tmp_path / "keywords.resource"
    resource.write_text(
        "*** Keywords ***\nUsed Keyword\n    Log    hi\n\nOrphan Keyword\n    No Operation\n",
        encoding="utf-8",
    )
    suite = tmp_path / "suite.robot"
    suite.write_text(
        "*** Settings ***\n"
        "Resource    keywords.resource\n"
        "Library     BuiltIn\n"
        "*** Variables ***\n"
        "${NAME}    Robot\n"
        "*** Test Cases ***\n"
        "Smoke\n"
        "    [Tags]    smoke\n"
        "    Used Keyword\n"
        "    Log    ${NAME}\n",
        encoding="utf-8",
    )

    suite_facts = extract_file_semantics(suite)
    kinds = {e.kind.value for e in suite_facts.entities}
    assert "suite" in kinds
    assert "test_case" in kinds
    assert "variable" in kinds
    assert "library" in kinds
    assert any(e.edge_kind.value == "imports_resource" for e in suite_facts.edges)
    assert any(e.edge_kind.value == "calls" and e.target_name == "Used Keyword" for e in suite_facts.edges)
    assert any(e.confidence.value == "low" for e in suite_facts.edges if e.edge_kind.value == "calls")


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


async def _seed_project(client: AsyncClient, tmp_path: Path) -> Path:
    location = tmp_path / "homes"
    location.mkdir()
    ws = await client.post(
        "/api/v1/workspaces",
        json={"name": "WS", "location": str(location)},
    )
    assert ws.status_code == 201, ws.text
    project = await client.post("/api/v1/projects", json={"name": "Demo"})
    assert project.status_code == 201, project.text
    return Path(project.json()["path"])


@pytest.mark.asyncio
async def test_variables_py_import_not_flagged_missing(api_client) -> None:
    """Variables *.py files are valid Robot imports but are not analysis entities."""
    client, _fresh, tmp_path = api_client
    project_path = await _seed_project(client, tmp_path)

    variables = project_path / "variables" / "env.py"
    variables.parent.mkdir(parents=True, exist_ok=True)
    variables.write_text("BASE_URL = 'https://example.test'\n", encoding="utf-8")

    suite = project_path / "tests" / "posts" / "posts_api.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Settings ***\n"
        "Variables    ../../variables/env.py\n"
        "*** Test Cases ***\n"
        "Smoke\n"
        "    No Operation\n",
        encoding="utf-8",
    )

    rebuilt = await client.post("/api/v1/index/rebuild?wait=true")
    assert rebuilt.status_code == 200, rebuilt.text

    report = await client.post("/api/v1/analysis/inspect", json={})
    assert report.status_code == 200, report.text
    missing = [
        f
        for f in report.json()["findings"]
        if f["inspection_id"] == "missing_import"
        and "env.py" in f["message"]
    ]
    assert missing == [], missing

    diag = await client.post(
        "/api/v1/language/diagnostics",
        json={"file_path": str(suite), "content": suite.read_text(encoding="utf-8")},
    )
    assert diag.status_code == 200, diag.text
    unresolved = [
        d
        for d in diag.json()["diagnostics"]
        if "env.py" in str(d.get("message", ""))
    ]
    assert unresolved == [], diag.json()


@pytest.mark.asyncio
async def test_stale_missing_import_cache_filtered_by_disk(api_client) -> None:
    """Epoch cache must not keep Variables *.py flagged after the file exists."""
    client, fresh, tmp_path = api_client
    project_path = await _seed_project(client, tmp_path)

    suite = project_path / "tests" / "api.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Settings ***\n"
        "Variables    ../variables/env.py\n"
        "*** Test Cases ***\n"
        "Smoke\n"
        "    No Operation\n",
        encoding="utf-8",
    )

    rebuilt = await client.post("/api/v1/index/rebuild?wait=true")
    assert rebuilt.status_code == 200, rebuilt.text

    # Before the file exists, missing_import should fire and populate cache.
    report = await client.post("/api/v1/analysis/inspect", json={})
    assert report.status_code == 200, report.text
    assert any(
        f["inspection_id"] == "missing_import" and "env.py" in f["message"]
        for f in report.json()["findings"]
    ), report.json()["findings"]

    variables = project_path / "variables" / "env.py"
    variables.parent.mkdir(parents=True, exist_ok=True)
    variables.write_text("BASE_URL = 'https://example.test'\n", encoding="utf-8")

    # No rebuild / epoch bump — post-filter must drop the stale cache hit.
    report2 = await client.post("/api/v1/analysis/inspect", json={})
    assert report2.status_code == 200, report2.text
    assert not any(
        f["inspection_id"] == "missing_import" and "env.py" in f["message"]
        for f in report2.json()["findings"]
    ), report2.json()["findings"]


@pytest.mark.asyncio
async def test_analysis_inspection_and_graph_apis(api_client) -> None:
    client, _fresh, tmp_path = api_client
    project_path = await _seed_project(client, tmp_path)

    resource = project_path / "resources" / "common.resource"
    resource.parent.mkdir(parents=True, exist_ok=True)
    resource.write_text(
        "*** Keywords ***\n"
        "Login User\n"
        "    [Documentation]    Shared login\n"
        "    Log    login\n"
        "\n"
        "Dead Keyword\n"
        "    No Operation\n",
        encoding="utf-8",
    )

    other = project_path / "resources" / "dup.resource"
    other.write_text(
        "*** Keywords ***\nLogin User\n    No Operation\n",
        encoding="utf-8",
    )

    suite = project_path / "tests" / "login.robot"
    suite.parent.mkdir(parents=True, exist_ok=True)
    suite.write_text(
        "*** Settings ***\n"
        "Resource    ../resources/common.resource\n"
        "Library     BuiltIn\n"
        "*** Variables ***\n"
        "${USER}    admin\n"
        "*** Test Cases ***\n"
        "Can Login\n"
        "    Login User\n"
        "    Log    ${USER}\n",
        encoding="utf-8",
    )

    broken = project_path / "tests" / "broken.robot"
    broken.write_text(
        "*** Settings ***\nResource    ../resources/missing.resource\n*** Test Cases ***\nX\n    No Operation\n",
        encoding="utf-8",
    )

    rebuilt = await client.post("/api/v1/index/rebuild?wait=true")
    assert rebuilt.status_code == 200, rebuilt.text

    snap = await client.get("/api/v1/analysis/snapshot")
    assert snap.status_code == 200, snap.text
    body = snap.json()
    assert body["entity_count"] >= 5
    assert body["graph_version"]
    assert body["incremental_revision"] >= 1
    assert body["timestamp"]

    catalog = await client.get("/api/v1/analysis/inspections")
    assert catalog.status_code == 200
    ids = {item["id"] for item in catalog.json()["inspections"]}
    assert {
        "unused_keyword",
        "unused_resource",
        "duplicate_keyword",
        "missing_import",
        "circular_dependency",
        "large_keyword",
    } <= ids

    report = await client.post("/api/v1/analysis/inspect", json={})
    assert report.status_code == 200, report.text
    payload = report.json()
    assert payload["graph_version"] == body["graph_version"]
    assert payload["incremental_revision"] == body["incremental_revision"]
    finding_ids = {f["inspection_id"] for f in payload["findings"]}
    assert "unused_keyword" in finding_ids
    assert "duplicate_keyword" in finding_ids
    assert "missing_import" in finding_ids
    assert any(
        "Potentially unused keyword 'Dead Keyword'" in f["message"]
        for f in payload["findings"]
    )
    assert all(f["confidence"] in {"exact", "high", "medium", "low"} for f in payload["findings"])

    one = await client.get("/api/v1/analysis/inspect/unused_keyword")
    assert one.status_code == 200
    assert one.json()["inspections_run"] == ["unused_keyword"]
    assert all(f["inspection_id"] == "unused_keyword" for f in one.json()["findings"])

    # Feature-specific Doctor endpoints must not exist
    assert (await client.get("/api/v1/analysis/unused-keywords")).status_code == 404
    assert (await client.get("/api/v1/analysis/duplicate-keywords")).status_code == 404

    callers = await client.get(
        "/api/v1/analysis/graph/keyword-callers",
        params={"keyword": "Login User"},
    )
    assert callers.status_code == 200, callers.text
    assert len(callers.json()["items"]) >= 1
    assert any(item.get("confidence") != "low" or item.get("target") for item in callers.json()["items"])

    callees = await client.get(
        "/api/v1/analysis/graph/keyword-callees",
        params={"keyword": "Login User"},
    )
    assert callees.status_code == 200
    assert any(item["target_name"] == "Log" for item in callees.json()["items"])

    deps = await client.get("/api/v1/analysis/graph/dependency")
    assert deps.status_code == 200
    assert len(deps.json()["nodes"]) >= 2

    affected = await client.post(
        "/api/v1/analysis/graph/affected-tests",
        json={"changed_symbols": ["Login User"]},
    )
    assert affected.status_code == 200, affected.text
    assert "Can Login" in {item["name"] for item in affected.json()["items"]}

    vars_refs = await client.get(
        "/api/v1/analysis/graph/variable-references",
        params={"variable": "${USER}"},
    )
    assert vars_refs.status_code == 200
    assert len(vars_refs.json()["items"]) >= 1

    libs = await client.get("/api/v1/analysis/graph/library-usage", params={"library": "BuiltIn"})
    assert libs.status_code == 200
    assert len(libs.json()["items"]) >= 1

    stats = await client.get("/api/v1/analysis/graph/keyword-usage-statistics")
    assert stats.status_code == 200
    assert any(
        item["entity"]["name"] == "Login User" and item["callers"] >= 1
        for item in stats.json()["items"]
    )

    again = await client.post("/api/v1/analysis/rebuild")
    assert again.status_code == 200
    assert again.json()["graph_version"]
    assert again.json()["incremental_revision"] >= 1
