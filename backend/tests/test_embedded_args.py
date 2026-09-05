"""Embedded-argument keywords (``Login with ${type} credential``)."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import InMemoryEventBus
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import Environment, Workspace
from robot_studio.infrastructure.analysis.embedded_args import (
    embedded_argument_variables,
    has_embedded_arguments,
    matches_embedded_keyword,
)
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.robot_language_service import (
    RobotLanguageService,
)


def test_embedded_argument_helpers() -> None:
    pattern = "Login to the application with ${type} credential"
    assert has_embedded_arguments(pattern)
    assert not has_embedded_arguments("Login User")
    assert embedded_argument_variables(pattern) == ("${type}",)
    assert embedded_argument_variables("Select ${n:\\d+} items") == ("${n}",)
    assert matches_embedded_keyword(pattern, "Login to the application with valid credential")
    assert matches_embedded_keyword(pattern, pattern)
    assert not matches_embedded_keyword(pattern, "Logout of the application")


def test_embedded_call_is_a_known_keyword() -> None:
    known = {"login to the application with ${type} credential", "log"}
    assert RobotLanguageService._is_known_keyword_call(
        "Login to the application with valid credential",
        known,
    )
    assert RobotLanguageService._is_known_keyword_call(
        "Given Login to the application with valid credential",
        known,
    )
    assert not RobotLanguageService._is_known_keyword_call(
        "Login to the application with extra leftover words",
        known,
    )


def test_embedded_args_are_declared_variables() -> None:
    lines = [
        "*** Keywords ***",
        "Login to the application with ${type} credential",
        "    Log    ${type}",
    ]
    declared = RobotLanguageService._collect_declared_variables(lines)
    assert "${type}" in declared


class _FakeBridge:
    def resolve_python(self, environment_path: Path | None) -> Path:
        assert environment_path is not None
        return environment_path / "bin" / "python"

    async def run(self, python_executable: Path, *, op: str, library: str = "", **_kwargs):
        if op == "resolve_library":
            if library.casefold() == "builtin":
                return {
                    "available": True,
                    "name": "BuiltIn",
                    "keywords": ["Log", "No Operation"],
                    "keyword_info": {},
                }
            return {"available": False, "name": library, "keywords": [], "keyword_info": {}}
        return []


@pytest.mark.asyncio
async def test_embedded_keyword_diagnostics_match_robot(tmp_path: Path) -> None:
    content = """*** Test Cases ***
Demo
    Login to the application with valid credential

*** Keywords ***
Login to the application with ${type} credential
    [Documentation]    Perform user login
    Log    ${type}
"""
    suite = tmp_path / "login.robot"
    suite.write_text(content, encoding="utf-8")

    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    workspace = Workspace(
        id=uuid4(),
        name="WS",
        path=tmp_path,
        created_at=datetime.now(UTC),
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
    assert not any("Unknown variable '${type}'" in msg for msg in messages)
    assert not any(
        "Unknown keyword 'Login to the application with valid credential'" in msg
        for msg in messages
    )


@pytest.mark.asyncio
async def test_definition_resolves_embedded_keyword_call(tmp_path: Path) -> None:
    store = SqliteIndexStore(tmp_path / "index.db")
    await store.initialize()
    await store.upsert_symbols(
        [
            {
                "id": "k1",
                "name": "Login to the application with ${type} credential",
                "kind": SymbolKind.KEYWORD.value,
                "file_path": str(tmp_path / "login.robot"),
                "line": 8,
                "documentation": "Perform user login",
                "detail": "",
            },
        ],
    )
    context = WorkspaceContext(InMemoryEventBus())
    service = RobotLanguageService(store=store, context=context)
    result = await service.definition(
        {"name": "Login to the application with valid credential"},
    )
    assert result is not None
    assert result["name"] == "Login to the application with ${type} credential"
    assert result["line"] == 8
