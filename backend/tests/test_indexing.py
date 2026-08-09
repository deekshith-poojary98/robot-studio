"""Unit tests for indexing, search, and language features."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.application.services.index_service import IndexService
from robot_studio.application.services.language_service import LanguageFacade
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import FileIndexed, FileRemoved, InMemoryEventBus, IndexUpdated
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import Project, ProjectType, Workspace, WorkspaceSettings
from robot_studio.infrastructure.indexing.file_watcher import NativeFileWatcher
from robot_studio.infrastructure.indexing.filesystem_indexer import FilesystemIndexer
from robot_studio.infrastructure.indexing.robot_indexer import RobotIndexer
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.builtin_keywords import BUILTIN_KEYWORDS
from robot_studio.infrastructure.language.robot_language_service import RobotLanguageService
from robot_studio.infrastructure.repositories.project_repository import (
    SqliteProjectRepository,
)


SAMPLE_ROBOT = """*** Settings ***
Library    Collections
Resource    common.resource
Documentation    Demo suite
Force Tags    smoke

*** Variables ***
${USER}    alice
@{ITEMS}    a    b

*** Keywords ***
Login User
    [Documentation]    Logs the user in
    [Arguments]    ${username}    ${password}=secret
    [Tags]    auth
    Log    ${USER}

*** Test Cases ***
Verify Login
    [Tags]    regression
    Login User
    Log    done
"""


@pytest.fixture
async def index_stack(tmp_path: Path):
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path / "WS",
        created_at=datetime.now(UTC),
        settings=WorkspaceSettings(),
    )
    workspace.path.mkdir()
    (workspace.path / "Projects").mkdir()
    await context.open(workspace)

    project_path = workspace.path / "Projects" / "Demo"
    project_path.mkdir()
    (project_path / "tests").mkdir()
    suite = project_path / "tests" / "demo.robot"
    suite.write_text(SAMPLE_ROBOT, encoding="utf-8")
    lib = project_path / "CustomLib.py"
    lib.write_text(
        'from robot.api.deco import keyword\n\n'
        'class CustomLib:\n'
        '    @keyword\n'
        '    def greet_user(self, name):\n'
        '        """Say hi"""\n'
        '        return name\n',
        encoding="utf-8",
    )

    db = tmp_path / "index.db"
    store = SqliteIndexStore(db)
    await store.initialize()
    projects = SqliteProjectRepository(db)
    await projects.initialize()
    project = Project(
        id=uuid4(),
        workspace_id=workspace.id,
        name="Demo",
        path=project_path,
        created_at=datetime.now(UTC),
        type=ProjectType.EMPTY,
    )
    await projects.create(project)

    indexer = FilesystemIndexer(store=store)
    watcher = NativeFileWatcher(debounce_seconds=0.2)
    service = IndexService(
        context=context,
        event_bus=bus,
        store=store,
        indexer=indexer,
        watcher=watcher,
        project_repository=projects,
    )
    service.start()
    language = RobotLanguageService(store=store, context=context, event_bus=bus)
    language.start()
    facade = LanguageFacade(context=context, language=language)
    try:
        yield service, store, facade, suite, lib, bus, workspace, project
    finally:
        await service.stop()
        await context.close()


def test_robot_indexer_extracts_symbols(tmp_path: Path) -> None:
    path = tmp_path / "demo.robot"
    path.write_text(SAMPLE_ROBOT, encoding="utf-8")
    symbols, refs = RobotIndexer().index_file(path, workspace_id=uuid4(), project_id=uuid4())
    kinds = {s.kind for s in symbols}
    names = {s.name for s in symbols}
    assert SymbolKind.KEYWORD.value in kinds
    assert SymbolKind.VARIABLE.value in kinds
    assert SymbolKind.TEST_CASE.value in kinds
    assert SymbolKind.LIBRARY.value in kinds
    assert "Login User" in names
    assert "${USER}" in names
    login = next(s for s in symbols if s.name == "Login User")
    assert "${username}" in login.detail
    assert "${password}=secret" in login.detail
    assert "Logs the user in" in login.documentation
    assert any(ref["name"] == "Login User" for ref in refs)


@pytest.mark.asyncio
async def test_incremental_indexing_skips_unchanged(index_stack) -> None:
    service, store, _facade, suite, _lib, _bus, workspace, project = index_stack
    count1, changed1 = await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )
    assert changed1 is True
    assert count1 > 0
    count2, changed2 = await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=False,
    )
    assert changed2 is False
    assert count2 == 0

    suite.write_text(SAMPLE_ROBOT + "\n# touch\n", encoding="utf-8")
    count3, changed3 = await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=False,
    )
    assert changed3 is True
    assert count3 > 0


@pytest.mark.asyncio
async def test_schedule_rebuild_returns_before_indexing_finishes(index_stack) -> None:
    service, _store, _facade, _suite, _lib, _bus, _workspace, _project = index_stack
    status = await service.schedule_rebuild(full=False)
    assert status.state == "indexing"
    task = service._rebuild_task
    assert task is not None
    await task
    ready = await service.get_status()
    assert ready.state == "ready"


def test_discover_files_prunes_venv(tmp_path: Path) -> None:
    root = tmp_path / "proj"
    root.mkdir()
    (root / "suite.robot").write_text("*** Test Cases ***\nA\n    Log  1\n", encoding="utf-8")
    venv_lib = root / ".venv" / "lib"
    venv_lib.mkdir(parents=True)
    (venv_lib / "site.py").write_text("x = 1\n", encoding="utf-8")
    node = root / "node_modules" / "pkg"
    node.mkdir(parents=True)
    (node / "index.py").write_text("y = 2\n", encoding="utf-8")

    found = FilesystemIndexer(store=object()).discover_files(root)  # type: ignore[arg-type]
    assert found == [root / "suite.robot"]


@pytest.mark.asyncio
async def test_rebuild_search_definition_references(index_stack) -> None:
    service, store, facade, suite, lib, bus, workspace, project = index_stack
    events: list[object] = []

    async def on_updated(event: IndexUpdated) -> None:
        events.append(event)

    async def on_indexed(event: FileIndexed) -> None:
        events.append(event)

    bus.subscribe(IndexUpdated, on_updated)
    bus.subscribe(FileIndexed, on_indexed)

    status = await service.rebuild()
    assert status.state == "ready"
    assert status.files_indexed >= 2
    assert status.keywords_indexed >= len(BUILTIN_KEYWORDS)
    assert any(isinstance(e, IndexUpdated) for e in events)

    results = await service.search("Login")
    assert any(item["name"] == "Login User" for item in results)

    keywords = await service.search("", kind=SymbolKind.KEYWORD)
    assert any(item["name"] == "Login User" for item in keywords)
    assert any(item["name"] == "Log" and item.get("file_path") == "BuiltIn" for item in keywords)

    builtin_hits = await service.search("Log", kind=SymbolKind.KEYWORD)
    assert any(item["name"] == "Log" for item in builtin_hits)

    suites = await service.search("", kind=SymbolKind.TEST_SUITE)
    assert suites, "expected at least one indexed test suite"

    definition = await facade.definition(name="Login User")
    assert definition is not None
    assert definition["file_path"] == str(suite)

    hover = await facade.hover(name="Login User")
    assert hover is not None
    assert "Logs the user in" in hover["documentation"]

    refs = await facade.references(name="Login User")
    assert any(ref["file_path"] == str(suite) for ref in refs)

    # Python library keyword
    py_results = await service.search("greet")
    assert any("greet" in item["name"].lower() for item in py_results)

    # YAML variables (QA-005) — index file directly to avoid watcher races.
    vars_yaml = suite.parent / "common.yaml"
    vars_yaml.write_text("BROWSER: chrome\nTIMEOUT: 30s\n", encoding="utf-8")
    await service.indexer.index_file(
        vars_yaml,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )
    yaml_hits = await store.search_symbols(query="BROWSER")
    assert any(
        item["name"] == "BROWSER" and str(item.get("file_path", "")).endswith("common.yaml")
        for item in yaml_hits
    ), yaml_hits

    # Tag search should dedupe (QA-006): Force Tags + Test Tags both "smoke".
    suite.write_text(
        suite.read_text(encoding="utf-8").replace(
            "Force Tags    smoke",
            "Force Tags    smoke\nDefault Tags    smoke",
        ),
        encoding="utf-8",
    )
    await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )
    tag_hits = await store.search_symbols(query="smoke", kind=SymbolKind.TAG)
    smoke = [item for item in tag_hits if item["name"] == "smoke"]
    assert len(smoke) == 1, smoke
    assert "used in" in (smoke[0].get("detail") or ""), smoke[0]


@pytest.mark.asyncio
async def test_empty_search_skips_tag_flood(index_stack) -> None:
    service, *_rest = index_stack
    await service.rebuild()
    bare = await service.search("")
    assert bare
    assert all(item.get("kind") != "tag" for item in bare)


@pytest.mark.asyncio
async def test_deleted_file_removed_from_index(index_stack) -> None:
    service, store, _facade, suite, _lib, bus, workspace, project = index_stack
    await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )
    assert await store.get_file_mtime(suite) is not None

    removed_events: list[FileRemoved] = []

    async def on_removed(event: FileRemoved) -> None:
        removed_events.append(event)

    bus.subscribe(FileRemoved, on_removed)
    suite.unlink()
    await service._on_file_change("deleted", suite)
    assert await store.get_file_mtime(suite) is None
    assert len(removed_events) == 1


@pytest.mark.asyncio
async def test_search_symbols_can_scope_libraries_to_workspace(tmp_path: Path) -> None:
    """Library Explorer must not list imports from other workspaces."""
    db = tmp_path / "index.db"
    store = SqliteIndexStore(db)
    await store.initialize()

    ws_a = uuid4()
    ws_b = uuid4()
    from robot_studio.domain.models import IndexedSymbol

    await store.upsert_symbols(
        [
            IndexedSymbol(
                id="lib-a",
                name="SeleniumLibrary",
                kind=SymbolKind.LIBRARY.value,
                file_path=tmp_path / "a" / "suite.robot",
                line=2,
                workspace_id=ws_a,
                project_id=uuid4(),
            ),
            IndexedSymbol(
                id="lib-b",
                name="Browser",
                kind=SymbolKind.LIBRARY.value,
                file_path=tmp_path / "b" / "suite.robot",
                line=2,
                workspace_id=ws_b,
                project_id=uuid4(),
            ),
        ]
    )

    scoped = await store.search_symbols(
        "",
        kind=SymbolKind.LIBRARY,
        workspace_id=ws_a,
        limit=50,
    )
    names = {item["name"] for item in scoped}
    assert names == {"SeleniumLibrary"}

    unscoped = await store.search_symbols("", kind=SymbolKind.LIBRARY, limit=50)
    assert {item["name"] for item in unscoped} == {"SeleniumLibrary", "Browser"}


@pytest.mark.asyncio
async def test_watcher_detects_new_file(index_stack, tmp_path: Path) -> None:
    service, store, _facade, suite, _lib, _bus, workspace, project = index_stack
    root = suite.parent
    service.watcher.watch_path(root)
    service.watcher.on_change = service._on_file_change
    await service.watcher.start()
    await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )

    new_file = root / "extra.robot"
    new_file.write_text("*** Test Cases ***\nExtra\n    Log    x\n", encoding="utf-8")
    await asyncio.sleep(0.6)
    assert await store.get_file_mtime(new_file) is not None
    await service.watcher.stop()
