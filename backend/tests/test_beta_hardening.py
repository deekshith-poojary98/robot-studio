"""Public-beta hardening: progress events, multi-definition, Problems/Analysis."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.container import Container
from robot_studio.core.events import AnalysisProgress, InMemoryEventBus, IndexProgress
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import Project, Workspace, WorkspaceSettings
from robot_studio.infrastructure.analysis.engine import RobotAnalysisEngine
from robot_studio.infrastructure.analysis.sqlite_analysis_store import SqliteAnalysisStore
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.robot_language_service import RobotLanguageService


@pytest.mark.asyncio
async def test_index_and_analysis_progress_fan_out(tmp_path: Path) -> None:
    container = Container()
    container.initialize()
    service = container.workspace_event_service
    assert service is not None
    bus = container.event_bus
    assert bus is not None

    queue = await service.subscribe()
    try:
        await bus.publish(
            IndexProgress(message="Indexing files", current=3, total=10, path="a.robot")
        )
        await bus.publish(
            AnalysisProgress(message="Binding imports", current=1, total=4)
        )
        messages = []
        for _ in range(4):
            try:
                messages.append(await asyncio.wait_for(queue.get(), timeout=1.0))
            except TimeoutError:
                break
        types = {item.get("type") for item in messages}
        assert "INDEX_PROGRESS" in types
        assert "ANALYSIS_PROGRESS" in types
        index_msg = next(item for item in messages if item["type"] == "INDEX_PROGRESS")
        assert index_msg["current"] == 3
        assert index_msg["total"] == 10
        assert "Indexing" in index_msg["message"]
    finally:
        await service.unsubscribe(queue)
        await container.shutdown()


@pytest.mark.asyncio
async def test_definition_returns_multiple_candidates(tmp_path: Path) -> None:
    db = tmp_path / "index.db"
    store = SqliteIndexStore(db)
    await store.initialize()
    await store.upsert_symbols(
        [
            {
                "id": "k1",
                "name": "Shared Keyword",
                "kind": SymbolKind.KEYWORD.value,
                "file_path": str(tmp_path / "a.robot"),
                "line": 2,
                "documentation": "",
                "detail": "",
            },
            {
                "id": "k2",
                "name": "Shared Keyword",
                "kind": SymbolKind.KEYWORD.value,
                "file_path": str(tmp_path / "b.robot"),
                "line": 5,
                "documentation": "",
                "detail": "",
            },
        ]
    )

    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    service = RobotLanguageService(store=store, context=context)
    result = await service.definition({"name": "Shared Keyword"})
    assert result is not None
    assert result["name"] == "Shared Keyword"
    assert isinstance(result.get("definitions"), list)
    assert len(result["definitions"]) == 2
    paths = {item["file_path"] for item in result["definitions"]}
    assert str(tmp_path / "a.robot") in paths
    assert str(tmp_path / "b.robot") in paths


def test_robot_cell_at_resolves_keyword_token() -> None:
    content = "*** Test Cases ***\nLogin\n    Shared Keyword    arg\n"
    token = RobotLanguageService._robot_cell_at(content, 3, 8)
    assert token == "Shared Keyword"


@pytest.mark.asyncio
async def test_analysis_missing_import_in_diagnostics(tmp_path: Path) -> None:
    """Problems should surface Analysis Engine missing_import findings."""
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    root = tmp_path / "proj"
    root.mkdir()
    suite = root / "login.robot"
    suite.write_text(
        "*** Settings ***\nResource    missing.resource\n\n*** Test Cases ***\nA\n    Log    x\n",
        encoding="utf-8",
    )
    workspace = Workspace(
        id=uuid4(),
        name="W",
        path=root,
        created_at=datetime.now(UTC),
        settings=WorkspaceSettings(),
    )
    project = Project(
        id=uuid4(),
        workspace_id=workspace.id,
        name="P",
        path=root,
        created_at=datetime.now(UTC),
    )
    await context.open(workspace)
    await context.set_active_project(project)

    analysis_db = tmp_path / "analysis.db"
    analysis_store = SqliteAnalysisStore(analysis_db)
    await analysis_store.initialize()
    engine = RobotAnalysisEngine(store=analysis_store, event_bus=bus)
    await engine.rebuild_project(
        project.id,
        workspace_id=workspace.id,
        roots=[root],
    )

    index_db = tmp_path / "index.db"
    index_store = SqliteIndexStore(index_db)
    await index_store.initialize()
    language = RobotLanguageService(
        store=index_store,
        context=context,
        analysis_engine=engine,
    )
    diagnostics = await language.diagnostics(
        {"file_path": str(suite), "content": suite.read_text(encoding="utf-8")}
    )
    analysis_hits = [
        d
        for d in diagnostics
        if d.get("source") == "analysis" or d.get("code") == "missing_import"
    ]
    assert analysis_hits, f"expected analysis missing_import, got {diagnostics}"
    assert any("missing.resource" in str(d.get("message")) for d in analysis_hits)
    assert all(d.get("inspection_id") == "missing_import" for d in analysis_hits)
