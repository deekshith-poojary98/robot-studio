"""Unit tests for env-aware library diagnostics."""

from __future__ import annotations

from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import InMemoryEventBus
from robot_studio.domain.models import Environment, Workspace
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.robot_language_service import (
    RobotLanguageService,
)
from robot_studio.infrastructure.language.robot_parsing_worker import (
    resolve_library,
    signature_help,
)


class _FakeBridge:
    def __init__(self, libraries: dict[str, dict]) -> None:
        self._libraries = {key.casefold(): value for key, value in libraries.items()}

    def resolve_python(self, environment_path: Path | None) -> Path:
        assert environment_path is not None
        return environment_path / "bin" / "python"

    async def run(
        self,
        python_executable: Path,
        *,
        op: str,
        library: str = "",
        content: str = "",
        file_path: str = "",
        line: int = 1,
        column: int = 1,
        **_kwargs,
    ):
        if op == "signature_help":
            return signature_help(content, file_path, line, column)
        if op == "completion_context":
            from robot_studio.infrastructure.language.robot_parsing_worker import (
                completion_context,
            )

            return completion_context(content, file_path, line, column)
        assert op == "resolve_library"
        key = library.casefold()
        if key in self._libraries:
            return self._libraries[key]
        # Path-style: allow lookup by basename stem (CustomLib.py → customlib).
        from pathlib import Path as _Path

        stem = _Path(library).stem.casefold()
        if stem in self._libraries:
            return self._libraries[stem]
        return {
            "available": False,
            "name": library,
            "keywords": [],
            "keyword_info": {},
        }


@pytest.mark.asyncio
async def test_resolve_library_worker_collections() -> None:
    result = resolve_library("Collections")
    assert result["available"] is True
    assert any(name == "Append To List" for name in result["keywords"])
    info = result["keyword_info"]["append to list"]
    assert info["parameters"]
    assert any("list" in p["label"].lower() for p in info["parameters"])


def test_resolve_library_keeps_complete_keyword_doc(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _Keyword:
        name = "Documented Keyword"
        short_doc = "One-line summary."
        doc = (
            "One-line summary.\n\n"
            "= Examples =\n"
            "| Documented Keyword | ${value} |\n\n"
            "- First detail\n"
            "- Second detail"
        )
        args: list[object] = []
        tags: list[str] = []
        deprecated = False
        lineno = 12

    class _Library:
        name = "FakeLibrary"
        source = "/tmp/fake_library.py"
        keywords = [_Keyword()]

    monkeypatch.setattr(
        "robot.libdoc.LibraryDocumentation",
        lambda _name: _Library(),
    )

    result = resolve_library("FakeLibrary")
    documentation = result["keyword_info"]["documented keyword"]["documentation"]

    assert documentation == _Keyword.doc
    assert "= Examples =" in documentation
    assert "Second detail" in documentation


@pytest.mark.parametrize(
    ("declared", "expected"),
    [("MARKDOWN", "MARKDOWN"), ("markdown", "MARKDOWN"), (None, "")],
)
def test_resolve_library_reports_doc_format(
    monkeypatch: pytest.MonkeyPatch,
    declared: str | None,
    expected: str,
) -> None:
    """The renderer needs ROBOT_LIBRARY_DOC_FORMAT to pick a markup dialect."""

    class _Keyword:
        name = "Add Sheet"
        doc = "Adds a **new sheet**."
        args: list[object] = []
        tags: list[str] = []
        deprecated = False
        lineno = 1

    class _Library:
        name = "MarkdownLibrary"
        source = "/tmp/markdown_library.py"
        doc_format = declared
        keywords = [_Keyword()]

    monkeypatch.setattr(
        "robot.libdoc.LibraryDocumentation",
        lambda _name: _Library(),
    )

    result = resolve_library("MarkdownLibrary")

    assert result["doc_format"] == expected
    # Every keyword carries it so the render site needs no library lookup.
    assert result["keyword_info"]["add sheet"]["doc_format"] == expected


@pytest.mark.asyncio
async def test_resolve_library_reports_robot_format_for_builtin() -> None:
    """libdoc defaults to ROBOT, which must stay sniffable downstream."""
    result = resolve_library("Collections")
    assert result["doc_format"] == "ROBOT"


def test_signature_help_keeps_multiword_keywords() -> None:
    content = """*** Test Cases ***
Demo
    Open Workbook    ${EXCEL_PATH}
"""
    result = signature_help(content, "demo.robot", line=3, column=10)
    assert result is not None
    assert result["keyword"] == "Open Workbook"
    assert result["arguments"] == ["${EXCEL_PATH}"]


def test_hover_signature_only_on_keyword_cell() -> None:
    content = """*** Test Cases ***
Demo
    Open Workbook    ${EXCEL_PATH}
"""
    row = content.splitlines()[2]
    # Column on the keyword
    kw_col = row.index("Open Workbook") + 1
    on_kw = signature_help(content, "demo.robot", line=3, column=kw_col, hover=True)
    assert on_kw is not None
    assert on_kw["keyword"] == "Open Workbook"

    # Column on the argument — no hover card
    arg_col = row.index("${EXCEL_PATH}") + 1
    on_arg = signature_help(content, "demo.robot", line=3, column=arg_col, hover=True)
    assert on_arg is None

    # Caret mode still resolves the call from the argument slot
    typing = signature_help(content, "demo.robot", line=3, column=arg_col, hover=False)
    assert typing is not None
    assert typing["keyword"] == "Open Workbook"


def test_hover_picks_nested_keyword_on_same_line() -> None:
    content = """*** Test Cases ***
Demo
    Run Keyword If    ${ok}    Log    hello
"""
    row = content.splitlines()[2]
    log_col = row.index("Log") + 1
    result = signature_help(content, "demo.robot", line=3, column=log_col, hover=True)
    assert result is not None
    assert result["keyword"] == "Log"

    outer_col = row.index("Run Keyword If") + 1
    outer = signature_help(content, "demo.robot", line=3, column=outer_col, hover=True)
    assert outer is not None
    assert outer["keyword"] == "Run Keyword If"


def test_signature_help_assignment_cell() -> None:
    content = """*** Test Cases ***
Demo
    ${data}    Fetch Sheet Data    Sheet1
"""
    result = signature_help(content, "demo.robot", line=3, column=28)
    assert result is not None
    assert result["keyword"] == "Fetch Sheet Data"
    assert result["arguments"] == ["Sheet1"]


@pytest.mark.asyncio
async def test_signature_help_uses_env_library_args(tmp_path: Path) -> None:
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()

    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)

    env_path = tmp_path / "new-env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    environment = Environment(
        id=uuid4(),
        workspace_id=workspace.id,
        name="new-env",
        path=env_path,
        python_version="3.13",
        python_executable=env_path / "bin" / "python",
        pip_executable=env_path / "bin" / "pip",
        created_at=workspace.created_at,
        is_active=True,
    )
    await context.set_active_environment(environment)

    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge(  # type: ignore[arg-type]
            {
                "ExcelSage": {
                    "available": True,
                    "name": "ExcelSage",
                    "keywords": ["Open Workbook"],
                    "keyword_info": {
                        "open workbook": {
                            "name": "Open Workbook",
                            "documentation": "Opens an Excel workbook.",
                            "parameters": [
                                {"label": "workbook_name: str", "documentation": ""},
                                {
                                    "label": "alias: str | None = None",
                                    "documentation": "default: None",
                                },
                            ],
                        },
                    },
                },
            },
        ),
    )

    content = """*** Settings ***
Library    ExcelSage

*** Test Cases ***
Demo
    Open Workbook    report.xlsx
"""
    result = await service.signature_help(
        {
            "file_path": "demo.robot",
            "line": 6,
            "column": 20,
            "content": content,
        },
    )
    assert result is not None
    assert result["keyword"] == "Open Workbook"
    assert result["documentation"] == "Opens an Excel workbook."
    assert [p["label"] for p in result["parameters"]] == [
        "workbook_name: str",
        "alias: str | None = None",
    ]


@pytest.mark.asyncio
async def test_semantic_diagnostics_use_env_libraries(tmp_path: Path) -> None:
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()

    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)

    env_path = tmp_path / "new-env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    environment = Environment(
        id=uuid4(),
        workspace_id=workspace.id,
        name="new-env",
        path=env_path,
        python_version="3.13",
        python_executable=env_path / "bin" / "python",
        pip_executable=env_path / "bin" / "pip",
        created_at=workspace.created_at,
        is_active=True,
    )
    await context.set_active_environment(environment)

    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge(  # type: ignore[arg-type]
            {
                "ExcelSage": {
                    "available": True,
                    "name": "ExcelSage",
                    "keywords": ["Open Workbook", "Fetch Sheet Data"],
                },
            },
        ),
    )

    content = """*** Settings ***
Library    ExcelSage

*** Test Cases ***
Demo
    Open Workbook    report.xlsx
    Fetch Sheet Data    Sheet1
"""
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, "demo.robot", diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert not any("Missing library" in msg for msg in messages)
    assert not any("Unknown keyword" in msg for msg in messages)

    bad = """*** Settings ***
Library    MissingLib

*** Test Cases ***
Demo
    Open Workbook    report.xlsx
"""
    diagnostics = []
    await service._append_semantic_diagnostics(bad, "demo.robot", diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert any("Missing library 'MissingLib'" in msg for msg in messages)
    assert any("Unknown keyword 'Open Workbook'" in msg for msg in messages)


@pytest.mark.asyncio
async def test_relative_python_library_path_is_not_missing(tmp_path: Path) -> None:
    """``Library ../helpers/CustomLib.py`` is relative to the suite file."""
    helpers = tmp_path / "helpers"
    tests = tmp_path / "tests"
    helpers.mkdir()
    tests.mkdir()
    custom = helpers / "CustomLib.py"
    custom.write_text(
        "class CustomLib:\n"
        "    ROBOT_LIBRARY_SCOPE = 'GLOBAL'\n"
        "    def custom_keyword(self):\n"
        "        pass\n",
        encoding="utf-8",
    )
    suite = tests / "login.robot"

    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)
    env_path = tmp_path / "new-env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    await context.set_active_environment(
        Environment(
            id=uuid4(),
            workspace_id=workspace.id,
            name="new-env",
            path=env_path,
            python_version="3.13",
            python_executable=env_path / "bin" / "python",
            pip_executable=env_path / "bin" / "pip",
            created_at=workspace.created_at,
            is_active=True,
        ),
    )

    abs_lib = str(custom.resolve())
    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge(  # type: ignore[arg-type]
            {
                abs_lib: {
                    "available": True,
                    "name": "CustomLib",
                    "keywords": ["Custom Keyword"],
                },
            },
        ),
    )
    content = """*** Settings ***
Library    ../helpers/CustomLib.py

*** Test Cases ***
Demo
    Custom Keyword
"""
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, str(suite), diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert not any("Missing library" in msg for msg in messages)
    assert not any("Unknown keyword" in msg for msg in messages)


@pytest.mark.asyncio
async def test_discover_library_imports_resolves_custom_py_and_skips_resources(
    tmp_path: Path,
) -> None:
    helpers = tmp_path / "helpers"
    tests = tmp_path / "tests"
    resources = tmp_path / "resources"
    helpers.mkdir()
    tests.mkdir()
    resources.mkdir()
    custom = helpers / "CustomLib.py"
    custom.write_text(
        "class CustomLib:\n"
        "    def custom_keyword(self):\n"
        "        pass\n",
        encoding="utf-8",
    )
    stray = tmp_path / "ExcelSage.py"
    stray.write_text("class ExcelSage:\n    def ping(self):\n        pass\n", encoding="utf-8")
    env_py = tmp_path / "env.py"
    env_py.write_text("BASE_URL = 'https://example.test'\n", encoding="utf-8")
    suite = tests / "login.robot"
    resource = resources / "login.resource"
    resource.write_text("*** Keywords ***\nDummy\n    No Operation\n", encoding="utf-8")

    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)

    from robot_studio.domain.interfaces.indexing import SymbolKind
    from robot_studio.domain.models import IndexedSymbol

    await store.upsert_symbols(
        [
            IndexedSymbol(
                id="lib-path",
                name="../helpers/CustomLib.py",
                kind=SymbolKind.LIBRARY.value,
                file_path=suite,
                line=6,
                workspace_id=workspace.id,
                detail="Library",
            ),
            IndexedSymbol(
                id="lib-py",
                name="CustomLib",
                kind=SymbolKind.LIBRARY.value,
                file_path=custom,
                line=1,
                workspace_id=workspace.id,
                detail="python",
            ),
            IndexedSymbol(
                id="lib-stray",
                name="ExcelSage",
                kind=SymbolKind.LIBRARY.value,
                file_path=stray,
                line=1,
                workspace_id=workspace.id,
                detail="python",
            ),
            IndexedSymbol(
                id="lib-env",
                name="env",
                kind=SymbolKind.LIBRARY.value,
                file_path=env_py,
                line=1,
                workspace_id=workspace.id,
                detail="python",
            ),
            IndexedSymbol(
                id="lib-res",
                name="../resources/login.resource",
                kind=SymbolKind.LIBRARY.value,
                file_path=suite,
                line=7,
                workspace_id=workspace.id,
            ),
            IndexedSymbol(
                id="lib-sel",
                name="SeleniumLibrary",
                kind=SymbolKind.LIBRARY.value,
                file_path=suite,
                line=3,
                workspace_id=workspace.id,
                detail="Library",
            ),
            IndexedSymbol(
                id="lib-from-resource",
                name="OperatingSystem",
                kind=SymbolKind.LIBRARY.value,
                file_path=resource,
                line=2,
                workspace_id=workspace.id,
                detail="Library",
            ),
        ],
    )

    env_path = tmp_path / "new-env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    await context.set_active_environment(
        Environment(
            id=uuid4(),
            workspace_id=workspace.id,
            name="new-env",
            path=env_path,
            python_version="3.13",
            python_executable=env_path / "bin" / "python",
            pip_executable=env_path / "bin" / "pip",
            created_at=workspace.created_at,
            is_active=True,
        ),
    )
    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge({}),  # type: ignore[arg-type]
    )
    discovered = await service._discover_library_imports()
    names = [name for name, _source in discovered]
    abs_custom = str(custom.resolve())
    assert abs_custom in names
    assert "SeleniumLibrary" in names
    assert "OperatingSystem" in names
    assert not any(item.endswith(".resource") for item in names)
    assert not any("login.resource" in item for item in names)
    assert "ExcelSage" not in names
    assert "env" not in names
    assert not any(Path(item).name.casefold() == "excelsage.py" for item in names)

    # End-to-end: relative/absolute custom lib appears in Library docs list.
    async def resolve_raw(name: str, file_path: str = "") -> dict:
        from robot_studio.infrastructure.language.robot_parsing_worker import (
            resolve_library as real_resolve,
        )

        return real_resolve(name, file_path)

    from robot_studio.infrastructure.language.library_catalog import LibraryCatalogService

    catalog = LibraryCatalogService(
        _resolve_raw=resolve_raw,
        _discover_imports=service._discover_library_imports,
    )
    listed = {lib.name for lib in await catalog.list_libraries()}
    assert "CustomLib" in listed
    assert "BuiltIn" in listed
    assert "ExcelSage" not in listed
    assert "env" not in listed


@pytest.mark.asyncio
async def test_missing_library_survives_indexed_import_symbol(tmp_path: Path) -> None:
    """Indexed Library import names must not silence Missing library after save."""
    from robot_studio.domain.interfaces.indexing import SymbolKind
    from robot_studio.domain.models import IndexedSymbol

    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()

    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)

    env_path = tmp_path / "new-env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    await context.set_active_environment(
        Environment(
            id=uuid4(),
            workspace_id=workspace.id,
            name="new-env",
            path=env_path,
            python_version="3.13",
            python_executable=env_path / "bin" / "python",
            pip_executable=env_path / "bin" / "pip",
            created_at=workspace.created_at,
            is_active=True,
        ),
    )

    # Simulate post-save reindex: unresolved Library import is stored as LIBRARY.
    await store.upsert_symbols(
        [
            IndexedSymbol(
                id="lib-missing",
                name="MissingLib",
                kind=SymbolKind.LIBRARY.value,
                file_path=tmp_path / "demo.robot",
                line=2,
                workspace_id=workspace.id,
            ),
        ],
    )

    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge({}),  # type: ignore[arg-type]
    )
    content = """*** Settings ***
Library    MissingLib

*** Test Cases ***
Demo
    Log    hi
"""
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, "demo.robot", diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert any("Missing library 'MissingLib'" in msg for msg in messages)


@pytest.mark.asyncio
async def test_completion_suggests_imported_library_keywords(tmp_path: Path) -> None:
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()

    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)

    env_path = tmp_path / "new-env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    await context.set_active_environment(
        Environment(
            id=uuid4(),
            workspace_id=workspace.id,
            name="new-env",
            path=env_path,
            python_version="3.13",
            python_executable=env_path / "bin" / "python",
            pip_executable=env_path / "bin" / "pip",
            created_at=workspace.created_at,
            is_active=True,
        ),
    )

    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge(  # type: ignore[arg-type]
            {
                "ExcelSage": {
                    "available": True,
                    "name": "ExcelSage",
                    "keywords": ["Open Workbook", "Fetch Sheet Data"],
                    "keyword_info": {
                        "open workbook": {
                            "name": "Open Workbook",
                            "documentation": "Opens an Excel workbook.",
                            "parameters": [],
                        },
                    },
                },
                "Collections": {
                    "available": True,
                    "name": "Collections",
                    "keywords": ["Append To List", "Get From List"],
                    "keyword_info": {},
                },
            },
        ),
    )

    content = """*** Settings ***
Library    ExcelSage
Library    Collections    WITH NAME    Col

*** Test Cases ***
Demo
    Open
"""
    items = await service.completion(
        {
            "file_path": "demo.robot",
            "line": 7,
            "column": 9,
            "content": content,
            "query": "Open",
        },
    )
    labels = [item["label"] for item in items]
    assert "Open Workbook" in labels
    open_items = [item for item in items if item["label"] == "Open Workbook"]
    assert open_items[0]["kind"] == "keyword"
    assert "ExcelSage" in open_items[0]["detail"]

    alias_content = """*** Settings ***
Library    ExcelSage
Library    Collections    WITH NAME    Col

*** Test Cases ***
Demo
    Col.App
"""
    alias_items = await service.completion(
        {
            "file_path": "demo.robot",
            "line": 7,
            "column": 12,
            "content": alias_content,
            "query": "Col.App",
        },
    )
    alias_labels = [item["label"] for item in alias_items]
    assert "Col.Append To List" in alias_labels


@pytest.mark.asyncio
async def test_completion_letter_a_does_not_flood_dsl(tmp_path: Path) -> None:
    """Typing ``A`` must not match FOR/IF via letters inside RANGE / ${a}."""
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)
    env_path = tmp_path / "env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    await context.set_active_environment(
        Environment(
            id=uuid4(),
            workspace_id=workspace.id,
            name="env",
            path=env_path,
            python_version="3.13",
            python_executable=env_path / "bin" / "python",
            pip_executable=env_path / "bin" / "pip",
            created_at=workspace.created_at,
            is_active=True,
        ),
    )
    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge(  # type: ignore[arg-type]
            {
                "MathLib": {
                    "available": True,
                    "name": "MathLib",
                    "keywords": ["Add Two Numbers"],
                    "keyword_info": {},
                },
            },
        ),
    )
    content = """*** Settings ***
Library    MathLib

*** Test Cases ***
Demo
    A
"""
    items = await service.completion(
        {
            "file_path": "demo.robot",
            "line": 6,
            "column": 6,
            "content": content,
            "query": "A",
        },
    )
    labels = [item["label"] for item in items]
    assert "Add Two Numbers" in labels
    assert "FOR" not in labels
    assert "IF" not in labels
    assert "TRY" not in labels
    assert "FINALLY" not in labels
    assert "BREAK" not in labels


@pytest.mark.asyncio
async def test_resolve_library_remote_available_without_server() -> None:
    """Remote is a standard RF library; a down XML-RPC server is not 'missing'."""
    result = resolve_library("Remote")
    assert result["available"] is True
    assert result["name"] == "Remote"
    assert result.get("source_type") == "remote"


@pytest.mark.asyncio
async def test_remote_library_import_with_as_alias_not_missing(
    tmp_path: Path,
) -> None:
    """User-guide style ``Library Remote … AS …`` must not warn Missing library."""
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)
    env_path = tmp_path / "env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    await context.set_active_environment(
        Environment(
            id=uuid4(),
            workspace_id=workspace.id,
            name="env",
            path=env_path,
            python_version="3.13",
            python_executable=env_path / "bin" / "python",
            pip_executable=env_path / "bin" / "pip",
            created_at=workspace.created_at,
            is_active=True,
        ),
    )
    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge(  # type: ignore[arg-type]
            {
                "Remote": {
                    "available": True,
                    "name": "Remote",
                    "keywords": [],
                    "keyword_info": {},
                    "source_type": "remote",
                },
            },
        ),
    )
    content = """*** Settings ***
Library    Remote    http://127.0.0.1:8270    AS    Example1
Library    Remote    http://example.com:8080/    AS    Example2
Library    Remote    http://10.0.0.2/example    1 minute    AS    Example3

*** Test Cases ***
Demo
    Log    hello
"""
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, "demo.robot", diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert not any("Missing library" in msg for msg in messages)


def test_imported_library_entries_accepts_as_alias() -> None:
    content = """*** Settings ***
Library    Remote    http://127.0.0.1:8270    AS    Example1
Library    Collections    WITH NAME    Col
"""
    entries = RobotLanguageService._imported_library_entries(content)
    assert ("Remote", "Example1") in entries
    assert ("Collections", "Col") in entries


def test_imported_libraries_follow_resource_chain(tmp_path: Path) -> None:
    """Libraries imported by a Resource are visible to importers (RF rule)."""
    resources = tmp_path / "resources"
    endpoints = resources / "endpoints"
    endpoints.mkdir(parents=True)
    (resources / "api_client.resource").write_text(
        "*** Settings ***\nLibrary    Collections\nLibrary    RequestsLibrary\n",
        encoding="utf-8",
    )
    leaf = endpoints / "comments.resource"
    leaf_content = (
        "*** Settings ***\n"
        "Resource    ../api_client.resource\n\n"
        "*** Keywords ***\n"
        "Check\n"
        "    Dictionary Should Contain Key    ${d}    id\n"
    )
    leaf.write_text(leaf_content, encoding="utf-8")

    names = RobotLanguageService._imported_libraries(leaf_content, str(leaf))
    assert "Collections" in names
    assert "RequestsLibrary" in names


@pytest.mark.asyncio
async def test_semantic_diagnostics_accept_transitive_resource_libraries(
    tmp_path: Path,
) -> None:
    resources = tmp_path / "resources"
    endpoints = resources / "endpoints"
    endpoints.mkdir(parents=True)
    (resources / "api_client.resource").write_text(
        "*** Settings ***\nLibrary    Collections\n",
        encoding="utf-8",
    )
    leaf = endpoints / "comments.resource"
    content = """*** Settings ***
Resource    ../api_client.resource

*** Keywords ***
Comment Should Match Schema Keys
    [Arguments]    ${comment}
    Dictionary Should Contain Key    ${comment}    id
"""
    leaf.write_text(content, encoding="utf-8")

    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)
    env_path = tmp_path / "env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    await context.set_active_environment(
        Environment(
            id=uuid4(),
            workspace_id=workspace.id,
            name="env",
            path=env_path,
            python_version="3.13",
            python_executable=env_path / "bin" / "python",
            pip_executable=env_path / "bin" / "pip",
            created_at=workspace.created_at,
            is_active=True,
        ),
    )
    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge(  # type: ignore[arg-type]
            {
                "Collections": {
                    "available": True,
                    "name": "Collections",
                    "keywords": ["Dictionary Should Contain Key"],
                },
            },
        ),
    )
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, str(leaf), diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert not any("Unknown keyword 'Dictionary Should Contain Key'" in msg for msg in messages)


@pytest.mark.asyncio
async def test_completion_suggests_as_alias_qualified_keywords(
    tmp_path: Path,
) -> None:
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    await context.open(workspace)
    env_path = tmp_path / "env"
    (env_path / "bin").mkdir(parents=True)
    (env_path / "bin" / "python").write_text("", encoding="utf-8")
    await context.set_active_environment(
        Environment(
            id=uuid4(),
            workspace_id=workspace.id,
            name="env",
            path=env_path,
            python_version="3.13",
            python_executable=env_path / "bin" / "python",
            pip_executable=env_path / "bin" / "pip",
            created_at=workspace.created_at,
            is_active=True,
        ),
    )
    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge(  # type: ignore[arg-type]
            {
                "Collections": {
                    "available": True,
                    "name": "Collections",
                    "keywords": ["Append To List", "Get From List"],
                    "keyword_info": {},
                },
            },
        ),
    )
    content = """*** Settings ***
Library    Collections    AS    Col

*** Test Cases ***
Demo
    Col.App
"""
    items = await service.completion(
        {
            "file_path": "demo.robot",
            "line": 6,
            "column": 12,
            "content": content,
            "query": "Col.App",
        },
    )
    labels = [item["label"] for item in items]
    assert "Col.Append To List" in labels
