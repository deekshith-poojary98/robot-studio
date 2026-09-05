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
from robot_studio.core.events import (
    FileIndexed,
    FileRemoved,
    IndexUpdated,
    InMemoryEventBus,
)
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import (
    Project,
    ProjectType,
    Workspace,
    WorkspaceSettings,
)
from robot_studio.infrastructure.indexing.file_watcher import NativeFileWatcher
from robot_studio.infrastructure.indexing.filesystem_indexer import FilesystemIndexer
from robot_studio.infrastructure.indexing.robot_indexer import (
    RobotIndexer,
    imported_indexable_paths,
)
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.builtin_keywords import BUILTIN_KEYWORDS
from robot_studio.infrastructure.language.robot_language_service import (
    RobotLanguageService,
)
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
    assert "username" in login.detail
    assert "password=secret" in login.detail
    assert "${username}" not in login.detail
    assert "Logs the user in" in login.documentation
    assert any(ref["name"] == "Login User" for ref in refs)


def test_is_tag_value_at_force_tags_and_local_tags() -> None:
    content = """*** Settings ***
Force Tags    comments    api
Resource      comments.resource

*** Test Cases ***
List
    [Tags]    comments    smoke
    No Operation
"""
    force = content.splitlines()[1]
    comments_col = force.index("comments") + 1
    api_col = force.index("api") + 1
    setting_col = force.index("Force") + 1
    assert RobotLanguageService._is_tag_value_at(content, 2, comments_col)
    assert RobotLanguageService._is_tag_value_at(content, 2, api_col)
    assert not RobotLanguageService._is_tag_value_at(content, 2, setting_col)

    resource = content.splitlines()[2]
    res_col = resource.index("comments") + 1
    assert not RobotLanguageService._is_tag_value_at(content, 3, res_col)

    tags = content.splitlines()[6]
    local_col = tags.index("comments") + 1
    assert RobotLanguageService._is_tag_value_at(content, 7, local_col)
    assert (
        RobotLanguageService._caret_definition_kind(content, 2, comments_col)
        is SymbolKind.TAG
    )
    assert RobotLanguageService._caret_definition_kind(content, 3, res_col) is None


@pytest.mark.asyncio
async def test_hover_force_tags_not_confused_with_resource(index_stack) -> None:
    service, _store, facade, suite, _lib, _bus, workspace, project = index_stack
    resource = suite.parent.parent / "resources" / "comments.resource"
    resource.parent.mkdir(parents=True, exist_ok=True)
    resource.write_text(
        "*** Keywords ***\nDo Comment\n    No Operation\n",
        encoding="utf-8",
    )
    content = (
        "*** Settings ***\n"
        "Resource    ../resources/comments.resource\n"
        "Force Tags    comments    api\n"
        "\n"
        "*** Test Cases ***\n"
        "List Comments\n"
        "    [Tags]    comments\n"
        "    No Operation\n"
    )
    suite.write_text(content, encoding="utf-8")
    await service.indexer.index_file(
        resource,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )
    await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )

    force_line = content.splitlines()[2]
    comments_col = force_line.index("comments") + 1
    hover = await facade.hover(
        name="comments",
        file_path=str(suite),
        line=3,
        column=comments_col,
        content=content,
    )
    assert hover is not None
    assert hover["kind"] == "tag"
    assert hover["name"] == "comments"

    import_hover = await facade.hover(name="comments")
    assert import_hover is not None
    assert import_hover["kind"] == "resource"


def test_symbol_lookup_names_strips_assign_and_extended_syntax() -> None:
    assert "${response}" in RobotLanguageService._symbol_lookup_names("${response}=")
    assert "${comment}" in RobotLanguageService._symbol_lookup_names("${comment}[id]")
    assert "${response}" in RobotLanguageService._symbol_lookup_names("${response.json()}")
    # Python Variables modules are indexed without ${…} braces.
    assert "KNOWN_COMMENT_ID" in RobotLanguageService._symbol_lookup_names(
        "${KNOWN_COMMENT_ID}",
    )


@pytest.mark.asyncio
async def test_hover_assignment_equals_and_extended_variable(index_stack) -> None:
    service, _store, facade, suite, _lib, _bus, workspace, project = index_stack
    content = (
        "*** Variables ***\n"
        "${KNOWN_COMMENT_ID}    1\n"
        "\n"
        "*** Test Cases ***\n"
        "Get Comment By Id\n"
        "    ${comment}    ${response}=    Log    ${KNOWN_COMMENT_ID}\n"
        "    Status Should Be    ${response}    200\n"
        "    Comment Should Match Schema Keys    ${comment}\n"
        "    Should Be Equal As Integers    ${comment}[id]    ${KNOWN_COMMENT_ID}\n"
    )
    suite.write_text(content, encoding="utf-8")
    await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )
    lines = content.splitlines()
    assign = lines[5]
    response_col = assign.index("${response}") + 2
    hover_eq = await facade.hover(
        name="${response}=",
        file_path=str(suite),
        line=6,
        column=response_col,
        content=content,
    )
    assert hover_eq is not None
    assert hover_eq["kind"] == "variable"
    assert hover_eq["name"] == "${response}"

    usage = lines[8]
    comment_col = usage.index("${comment}") + 2
    hover_ext = await facade.hover(
        name="${comment}[id]",
        file_path=str(suite),
        line=9,
        column=comment_col,
        content=content,
    )
    assert hover_ext is not None
    assert hover_ext["kind"] == "variable"
    assert hover_ext["name"] == "${comment}"

    known_col = usage.index("${KNOWN_COMMENT_ID}") + 2
    hover_known = await facade.hover(
        name="${KNOWN_COMMENT_ID}",
        file_path=str(suite),
        line=9,
        column=known_col,
        content=content,
    )
    assert hover_known is not None
    assert hover_known["kind"] == "variable"
    assert hover_known["name"] == "${KNOWN_COMMENT_ID}"


@pytest.mark.asyncio
async def test_hover_variables_py_import(index_stack) -> None:
    service, store, facade, suite, _lib, _bus, workspace, project = index_stack
    env = suite.parent / "env.py"
    env.write_text("KNOWN_COMMENT_ID = 42\n", encoding="utf-8")
    content = (
        "*** Settings ***\n"
        "Variables    env.py\n"
        "\n"
        "*** Test Cases ***\n"
        "Get Comment By Id\n"
        "    Should Be Equal As Integers    ${comment}[id]    ${KNOWN_COMMENT_ID}\n"
    )
    suite.write_text(content, encoding="utf-8")
    await service.indexer.index_file(
        env,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )
    await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )
    indexed = await store.search_symbols(
        query="${KNOWN_COMMENT_ID}",
        workspace_id=workspace.id,
        project_id=project.id,
        kind=SymbolKind.VARIABLE,
    )
    assert any(
        item["name"] == "${KNOWN_COMMENT_ID}"
        and Path(item["file_path"]).name == "env.py"
        for item in indexed
    )
    usage = content.splitlines()[5]
    known_col = usage.index("${KNOWN_COMMENT_ID}") + 2
    hover = await facade.hover(
        name="${KNOWN_COMMENT_ID}",
        file_path=str(suite),
        line=6,
        column=known_col,
        content=content,
    )
    assert hover is not None
    assert hover["kind"] == "variable"
    assert hover["name"] == "${KNOWN_COMMENT_ID}"
    assert Path(hover["file_path"]).name == "env.py"


@pytest.mark.asyncio
async def test_hover_variables_py_import_without_index(index_stack) -> None:
    """Variables *.py still hover when the module is not indexed yet."""
    _service, _store, facade, suite, _lib, _bus, _workspace, _project = index_stack
    env = suite.parent / "env.py"
    env.write_text("KNOWN_COMMENT_ID = 42\n", encoding="utf-8")
    content = (
        "*** Settings ***\n"
        "Variables    env.py\n"
        "\n"
        "*** Test Cases ***\n"
        "Use Known Id\n"
        "    Log    ${KNOWN_COMMENT_ID}\n"
    )
    suite.write_text(content, encoding="utf-8")
    usage = content.splitlines()[5]
    known_col = usage.index("${KNOWN_COMMENT_ID}") + 2
    hover = await facade.hover(
        name="${KNOWN_COMMENT_ID}",
        file_path=str(suite),
        line=6,
        column=known_col,
        content=content,
    )
    assert hover is not None
    assert hover["kind"] == "variable"
    assert hover["name"] == "${KNOWN_COMMENT_ID}"
    assert Path(hover["file_path"]).name == "env.py"
    assert hover["line"] == 1


def test_imported_indexable_paths_resolves_resource_and_variables(tmp_path: Path) -> None:
    resource = tmp_path / "common.resource"
    resource.write_text("*** Variables ***\n${SHARED}    hello\n", encoding="utf-8")
    env = tmp_path / "env.py"
    env.write_text("KNOWN_ID = 1\n", encoding="utf-8")
    suite = tmp_path / "suite.robot"
    suite.write_text(
        "*** Settings ***\n"
        "Resource    common.resource\n"
        "Variables    env.py\n"
        "Resource    ${DYNAMIC}.resource\n"
        "Resource    missing.resource\n",
        encoding="utf-8",
    )
    found = {path.name for path in imported_indexable_paths(suite)}
    assert found == {"common.resource", "env.py"}


@pytest.mark.asyncio
async def test_index_file_follows_resource_variable_chain(index_stack) -> None:
    """Indexing a suite must pull in imported .resource variables (no hover AST)."""
    service, store, facade, suite, _lib, _bus, workspace, project = index_stack
    deeper = suite.parent / "deeper.resource"
    deeper.write_text(
        "*** Variables ***\n${NESTED}    inner\n",
        encoding="utf-8",
    )
    common = suite.parent / "common.resource"
    common.write_text(
        "*** Settings ***\n"
        "Resource    deeper.resource\n"
        "\n"
        "*** Variables ***\n"
        "${SHARED}    hello\n",
        encoding="utf-8",
    )
    content = (
        "*** Settings ***\n"
        "Resource    common.resource\n"
        "\n"
        "*** Test Cases ***\n"
        "Use Shared\n"
        "    Log    ${SHARED}\n"
        "    Log    ${NESTED}\n"
    )
    suite.write_text(content, encoding="utf-8")
    await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )

    hits = await store.search_symbols(
        query="SHARED",
        workspace_id=workspace.id,
        project_id=project.id,
    )
    assert any(
        item["name"] == "${SHARED}"
        and Path(item["file_path"]).name == "common.resource"
        for item in hits
    )
    nested = await store.search_symbols(
        query="NESTED",
        workspace_id=workspace.id,
        project_id=project.id,
    )
    assert any(
        item["name"] == "${NESTED}"
        and Path(item["file_path"]).name == "deeper.resource"
        for item in nested
    )

    usage = content.splitlines()[5]
    shared_col = usage.index("${SHARED}") + 2
    hover = await facade.hover(
        name="${SHARED}",
        file_path=str(suite),
        line=6,
        column=shared_col,
        content=content,
    )
    assert hover is not None
    assert hover["kind"] == "variable"
    assert hover["name"] == "${SHARED}"
    assert Path(hover["file_path"]).name == "common.resource"


@pytest.mark.asyncio
async def test_index_file_follows_cyclic_resources(index_stack) -> None:
    service, store, _facade, suite, _lib, _bus, workspace, project = index_stack
    first = suite.parent / "a.resource"
    second = suite.parent / "b.resource"
    first.write_text("*** Settings ***\nResource    b.resource\n", encoding="utf-8")
    second.write_text("*** Settings ***\nResource    a.resource\n", encoding="utf-8")
    suite.write_text(
        "*** Settings ***\nResource    a.resource\n",
        encoding="utf-8",
    )
    await service.indexer.index_file(
        suite,
        workspace_id=workspace.id,
        project_id=project.id,
        force=True,
    )
    files = await store.list_indexed_files(workspace.id)
    names = {Path(item).name for item in files}
    assert {"a.resource", "b.resource", suite.name} <= names


@pytest.mark.asyncio
async def test_incremental_indexing_skips_unchanged(index_stack) -> None:
    service, _store, _facade, suite, _lib, _bus, workspace, project = index_stack
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


@pytest.mark.asyncio
async def test_incremental_rebuild_skips_unchanged_files(index_stack) -> None:
    service, store, _facade, suite, _lib, _bus, _workspace, _project = index_stack
    await service.rebuild()
    before = await store.get_file_mtime(suite)
    assert before is not None

    status = await service.schedule_rebuild(full=False)
    assert status.state == "indexing"
    await service._rebuild_task
    after = await store.get_file_mtime(suite)
    assert after == before
    ready = await service.get_status()
    assert ready.state == "ready"
    assert ready.files_indexed >= 2


@pytest.mark.asyncio
async def test_project_opened_does_not_wipe_index(index_stack) -> None:
    """Relaunch opens the project after the workspace — must stay incremental."""
    from robot_studio.core.events import ProjectOpened

    service, store, _facade, suite, _lib, bus, workspace, project = index_stack
    await service.rebuild()
    mtime = await store.get_file_mtime(suite)
    assert mtime is not None

    await bus.publish(
        ProjectOpened(workspace_id=workspace.id, project_id=project.id),
    )
    # Give the handler a turn; it should be a no-op.
    await asyncio.sleep(0)
    task = service._rebuild_task
    if task is not None and not task.done():
        await task
    assert await store.get_file_mtime(suite) == mtime


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
    service, store, facade, suite, _lib, bus, workspace, project = index_stack
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
    assert hover["detail_kind"] == "signature"
    assert "username" in hover["detail"]

    case_hover = await facade.hover(name="Verify Login")
    assert case_hover is not None
    assert case_hover["kind"] == "test_case"
    assert case_hover["detail_kind"] == "annotation"
    assert str(case_hover["detail"]).startswith("test case")

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
async def test_index_service_search_stays_in_active_workspace(index_stack) -> None:
    """Completions / Go to Symbol must not pull keywords from other workspaces."""
    service, store, _facade, _suite, _lib, _bus, workspace, project = index_stack
    from robot_studio.domain.models import IndexedSymbol

    other_ws = uuid4()
    await store.upsert_symbols(
        [
            IndexedSymbol(
                id="foreign-kw",
                name="create robot file",
                kind=SymbolKind.KEYWORD.value,
                file_path=Path("/tmp/other/generate_robot_tests.py"),
                line=20,
                workspace_id=other_ws,
                project_id=uuid4(),
            ),
            IndexedSymbol(
                id="local-kw",
                name="Login User",
                kind=SymbolKind.KEYWORD.value,
                file_path=workspace.path / "Projects" / "Demo" / "tests" / "demo.robot",
                line=10,
                workspace_id=workspace.id,
                project_id=project.id,
            ),
        ]
    )

    hits = await service.search("create", kind=SymbolKind.KEYWORD)
    names = {item["name"] for item in hits}
    assert "create robot file" not in names

    local = await service.search("Login", kind=SymbolKind.KEYWORD)
    assert any(item["name"] == "Login User" for item in local)


@pytest.mark.asyncio
async def test_definition_stays_in_active_workspace(index_stack) -> None:
    """Go to Definition must not list symbols from a previously opened project."""
    _service, store, facade, _suite, _lib, _bus, workspace, project = index_stack
    from robot_studio.domain.models import IndexedSymbol

    other_ws = uuid4()
    local_file = workspace.path / "Projects" / "Demo" / "tests" / "posts_api.robot"
    await store.upsert_symbols(
        [
            IndexedSymbol(
                id="foreign-tag",
                name="api",
                kind=SymbolKind.TAG.value,
                file_path=Path("/tmp/OrangeHRM/tests/smoke_test.robot"),
                line=6,
                workspace_id=other_ws,
                project_id=uuid4(),
            ),
            IndexedSymbol(
                id="local-tag",
                name="api",
                kind=SymbolKind.TAG.value,
                file_path=local_file,
                line=5,
                workspace_id=workspace.id,
                project_id=project.id,
            ),
        ]
    )

    result = await facade.definition(name="api")
    assert result is not None
    candidates = result.get("definitions") or [result]
    paths = {str(item["file_path"]) for item in candidates}
    assert str(local_file) in paths
    assert not any("OrangeHRM" in path for path in paths)


@pytest.mark.asyncio
async def test_find_definitions_prefers_active_project(tmp_path: Path) -> None:
    db = tmp_path / "index.db"
    store = SqliteIndexStore(db)
    await store.initialize()
    from robot_studio.domain.models import IndexedSymbol

    ws = uuid4()
    project_a = uuid4()
    project_b = uuid4()
    await store.upsert_symbols(
        [
            IndexedSymbol(
                id="tag-other",
                name="api",
                kind=SymbolKind.TAG.value,
                file_path=tmp_path / "aaa" / "suite.robot",
                line=2,
                workspace_id=ws,
                project_id=project_b,
            ),
            IndexedSymbol(
                id="tag-current",
                name="api",
                kind=SymbolKind.TAG.value,
                file_path=tmp_path / "zzz" / "suite.robot",
                line=5,
                workspace_id=ws,
                project_id=project_a,
            ),
        ]
    )

    hits = await store.find_definitions(
        "api",
        workspace_id=ws,
        project_id=project_a,
    )
    assert [item["id"] for item in hits] == ["tag-current", "tag-other"]

    foreign = await store.find_definitions("api", workspace_id=uuid4())
    assert foreign == []


@pytest.mark.asyncio
async def test_find_definitions_ranks_by_caret_context(tmp_path: Path) -> None:
    db = tmp_path / "index.db"
    store = SqliteIndexStore(db)
    await store.initialize()
    from robot_studio.domain.models import IndexedSymbol

    ws = uuid4()
    await store.upsert_symbols(
        [
            IndexedSymbol(
                id="res-comments",
                name="comments",
                kind=SymbolKind.RESOURCE.value,
                file_path=tmp_path / "comments.resource",
                line=1,
                workspace_id=ws,
            ),
            IndexedSymbol(
                id="tag-comments",
                name="comments",
                kind=SymbolKind.TAG.value,
                file_path=tmp_path / "suite.robot",
                line=3,
                workspace_id=ws,
            ),
        ]
    )
    default = await store.find_definitions("comments", workspace_id=ws)
    assert [item["id"] for item in default] == ["res-comments", "tag-comments"]
    on_tag = await store.find_definitions(
        "comments",
        workspace_id=ws,
        prefer_kinds=[SymbolKind.TAG],
    )
    assert [item["id"] for item in on_tag] == ["tag-comments", "res-comments"]


@pytest.mark.asyncio
async def test_watcher_index_finalizes_analysis_once(index_stack) -> None:
    service, _store, _facade, suite, _lib, _bus, _workspace, _project = index_stack

    class FakeEngine:
        def __init__(self) -> None:
            self.ingests: list[bool] = []
            self.finalizes = 0

        async def ingest_file(self, path, *, workspace_id, project_id, rebind=True):
            self.ingests.append(rebind)

        async def finalize_project(self, project_id):
            self.finalizes += 1

        async def remove_file(self, path, *, project_id, rebind=True):
            return None

    engine = FakeEngine()
    service.indexer.analysis_engine = engine
    other = suite.parent / "other.robot"
    other.write_text("*** Test Cases ***\nB\n    Log    1\n", encoding="utf-8")
    suite.write_text(SAMPLE_ROBOT + "\n# changed\n", encoding="utf-8")
    await service._on_file_change("modified", suite)
    await service._on_file_change("modified", other)
    await asyncio.sleep(0)
    assert engine.ingests
    assert all(flag is False for flag in engine.ingests)
    assert engine.finalizes == 1


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


def test_parse_indexable_file_is_picklable(tmp_path: Path) -> None:
    from robot_studio.infrastructure.indexing.filesystem_indexer import (
        parse_indexable_file,
    )

    path = tmp_path / "demo.robot"
    path.write_text(SAMPLE_ROBOT, encoding="utf-8")
    ws = str(uuid4())
    proj = str(uuid4())
    payload = parse_indexable_file(str(path), ws, proj)
    assert payload.error is None
    assert any(s["name"] == "Login User" for s in payload.symbols)
    names = {s["name"] for s in payload.symbols}
    assert "Verify Login" in names


@pytest.mark.asyncio
async def test_parallel_rebuild_indexes_many_files(index_stack, monkeypatch) -> None:
    """Process-pool path must produce the same searchable index as serial."""
    monkeypatch.setattr(
        "robot_studio.application.services.index_service._index_worker_count",
        lambda: 2,
    )
    service, _store, _facade, suite, _lib, _bus, _workspace, _project = index_stack
    tests_dir = suite.parent
    for i in range(6):
        (tests_dir / f"bulk_{i}.robot").write_text(
            f"*** Test Cases ***\nCase {i}\n    Log    {i}\n\n"
            f"*** Keywords ***\nBulk Keyword {i}\n    Log    kw{i}\n",
            encoding="utf-8",
        )

    status = await service.rebuild()
    assert status.state == "ready"
    assert status.files_indexed >= 7  # demo + CustomLib + 6 bulk

    hits = await service.search("Bulk Keyword 3", kind=SymbolKind.KEYWORD)
    assert any(item["name"] == "Bulk Keyword 3" for item in hits)
    cases = await service.search("Case 5", kind=SymbolKind.TEST_CASE)
    assert any(item["name"] == "Case 5" for item in cases)


@pytest.mark.asyncio
async def test_parallel_rebuild_cancel_is_safe(index_stack, monkeypatch) -> None:
    monkeypatch.setattr(
        "robot_studio.application.services.index_service._index_worker_count",
        lambda: 2,
    )
    service, _store, _facade, suite, _lib, _bus, _workspace, _project = index_stack
    tests_dir = suite.parent
    for i in range(12):
        (tests_dir / f"cancel_{i}.robot").write_text(
            f"*** Test Cases ***\nCancel {i}\n    Log    {i}\n",
            encoding="utf-8",
        )

    await service.schedule_rebuild(full=True)
    task = service._rebuild_task
    assert task is not None
    await asyncio.sleep(0)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task

    # A fresh rebuild after cancel must still complete.
    status = await service.rebuild()
    assert status.state == "ready"


def test_use_process_pool_disabled_when_frozen(monkeypatch) -> None:
    from robot_studio.application.services import index_service as mod

    monkeypatch.setattr(mod.sys, "platform", "linux", raising=False)
    monkeypatch.setattr(mod.sys, "frozen", True, raising=False)
    assert mod._use_process_pool(20, 2) is False

    monkeypatch.setattr(mod.sys, "frozen", False, raising=False)
    monkeypatch.setattr(mod.sys, "platform", "win32", raising=False)
    assert mod._use_process_pool(20, 2) is False

    monkeypatch.setattr(mod.sys, "platform", "darwin", raising=False)
    assert mod._use_process_pool(20, 2) is True
    assert mod._use_process_pool(1, 2) is False
