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
        return self._libraries.get(
            library.casefold(),
            {"available": False, "name": library, "keywords": [], "keyword_info": {}},
        )


@pytest.mark.asyncio
async def test_resolve_library_worker_collections() -> None:
    result = resolve_library("Collections")
    assert result["available"] is True
    assert any(name == "Append To List" for name in result["keywords"])
    info = result["keyword_info"]["append to list"]
    assert info["parameters"]
    assert any("list" in p["label"].lower() for p in info["parameters"])


def test_signature_help_keeps_multiword_keywords() -> None:
    content = """*** Test Cases ***
Demo
    Open Workbook    ${EXCEL_PATH}
"""
    result = signature_help(content, "demo.robot", line=3, column=10)
    assert result is not None
    assert result["keyword"] == "Open Workbook"
    assert result["arguments"] == ["${EXCEL_PATH}"]


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
