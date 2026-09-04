"""Regression: syntax-highlight sample should not flood Problems with false positives."""

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
from robot_studio.infrastructure.language.robot_parsing_worker import signature_help

SAMPLE = Path(__file__).with_name("fixtures") / "syntax_highlight_sample.robot"


class _FakeBridge:
    def resolve_python(self, environment_path: Path | None) -> Path:
        assert environment_path is not None
        return environment_path / "bin" / "python"

    async def run(self, python_executable: Path, *, op: str, library: str = "", **kwargs):
        if op == "signature_help":
            return signature_help(
                str(kwargs.get("content") or ""),
                str(kwargs.get("file_path") or ""),
                int(kwargs.get("line") or 1),
                int(kwargs.get("column") or 1),
            )
        if op == "resolve_library":
            if library.casefold() in {"builtin", "collections"}:
                return {
                    "available": True,
                    "name": library,
                    "keywords": [
                        "Log",
                        "Log To Console",
                        "Set Variable",
                        "Create List",
                        "Create Dictionary",
                        "Should Be Equal",
                        "Should Not Be Equal",
                        "Should Be True",
                        "Should Not Be True",
                        "Should Contain",
                        "Should Start With",
                        "Should End With",
                        "No Operation",
                        "Sleep",
                        "Evaluate",
                        "Catenate",
                        "Fail",
                        "Run Keyword",
                        "Run Keywords",
                        "Run Keyword If",
                        "Wait Until Keyword Succeeds",
                        "Skip",
                        "Pass Execution",
                    ],
                    "keyword_info": {},
                }
            return {"available": False, "name": library, "keywords": [], "keyword_info": {}}
        if op == "diagnostics":
            return []
        raise AssertionError(f"unexpected op {op}")


@pytest.mark.asyncio
async def test_syntax_sample_has_no_false_positive_semantics(tmp_path: Path) -> None:
    content = SAMPLE.read_text(encoding="utf-8")
    suite = tmp_path / "syntax.robot"
    suite.write_text(content, encoding="utf-8")
    # Stub imports referenced by the sample so Missing resource/variables stay real-only.
    (tmp_path / "keywords.resource").write_text("*** Keywords ***\n", encoding="utf-8")
    (tmp_path / "variables.py").write_text("URL = 'x'\n", encoding="utf-8")

    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(__import__("datetime").UTC),
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
        parsing=_FakeBridge(),  # type: ignore[arg-type]
    )
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, str(suite), diagnostics)
    messages = [item["message"] for item in diagnostics]

    assert not any("Unknown keyword '...'" in msg for msg in messages)
    assert not any("Unknown variable '${TRUE}'" in msg for msg in messages)
    assert not any("Unknown variable '${FALSE}'" in msg for msg in messages)
    assert not any("Unknown variable '${item}'" in msg for msg in messages)
    assert not any("Unknown variable '${message}'" in msg for msg in messages)
    assert not any("Unknown variable '${local}'" in msg for msg in messages)
    assert not any("Unknown variable '@{numbers}'" in msg for msg in messages)
    assert not any("Unknown variable '&{user}'" in msg for msg in messages)
    assert messages == [], f"unexpected semantic diagnostics: {messages}"


@pytest.mark.asyncio
async def test_missing_resource_and_variables_both_reported(tmp_path: Path) -> None:
    content = """*** Settings ***
Resource    keywords.resource
Variables   variables.py

*** Test Cases ***
Demo
    No Operation
"""
    suite = tmp_path / "suite.robot"
    suite.write_text(content, encoding="utf-8")

    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(__import__("datetime").UTC),
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
    # Index the import statements (previously made Missing resource disappear).
    await store.upsert_symbols(
        [
            {
                "id": "res-import",
                "name": "keywords.resource",
                "kind": "resource",
                "file_path": str(suite),
                "line": 2,
                "detail": "Resource",
            },
        ],
    )

    service = RobotLanguageService(
        store=store,
        context=context,
        parsing=_FakeBridge(),  # type: ignore[arg-type]
    )
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, str(suite), diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert "Missing resource 'keywords.resource'" in messages
    assert "Missing variables file 'variables.py'" in messages


@pytest.mark.asyncio
async def test_number_variables_are_not_unknown(tmp_path: Path) -> None:
    content = """*** Test Cases ***
Numbers
    Should Be Equal As Numbers    ${10}    10
    Log    ${20}
    Log    ${3.14}
    Log    ${0xFF}
    Log    ${1_000}
"""
    suite = tmp_path / "numbers.robot"
    suite.write_text(content, encoding="utf-8")

    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=__import__("datetime").datetime.now(__import__("datetime").UTC),
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
        parsing=_FakeBridge(),  # type: ignore[arg-type]
    )
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, str(suite), diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert not any("Unknown variable '${10}'" in msg for msg in messages)
    assert not any("Unknown variable '${20}'" in msg for msg in messages)
    assert not any("Unknown variable '${3.14}'" in msg for msg in messages)
    assert not any("Unknown variable '${0xFF}'" in msg for msg in messages)
    assert not any("Unknown variable '${1_000}'" in msg for msg in messages)
    assert not any(msg.startswith("Unknown variable") for msg in messages)
