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
    return service, store, facade, suite, lib, bus, workspace, project


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
async def test_rebuild_search_definition_references(index_stack) -> None:
    service, store, facade, suite, lib, bus, _workspace, _project = index_stack
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
    assert lib.exists()


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
