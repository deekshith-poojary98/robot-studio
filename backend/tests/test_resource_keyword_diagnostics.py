"""User keywords from imported Resource files must not be Unknown keyword."""

from __future__ import annotations

from datetime import UTC, datetime
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
            if library.casefold() == "builtin":
                return {
                    "available": True,
                    "name": "BuiltIn",
                    "keywords": ["No Operation", "Log"],
                    "keyword_info": {},
                }
            return {"available": False, "name": library, "keywords": [], "keyword_info": {}}
        if op == "diagnostics":
            return []
        raise AssertionError(f"unexpected op {op}")


async def _service(tmp_path: Path) -> tuple[RobotLanguageService, Path]:
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
    return service, tmp_path


@pytest.mark.asyncio
async def test_workflow_resource_keywords_are_known(tmp_path: Path) -> None:
    service, root = await _service(tmp_path)
    (root / "workflow").mkdir()
    (root / "workflow" / "reset_password_workflow.robot").write_text(
        "*** Keywords ***\n"
        "Reset Password Page Should Be Loaded\n"
        "    No Operation\n"
        "All Password Rules Should Be Unmet\n"
        "    No Operation\n"
        "Type New Password Progressively\n"
        "    [Arguments]    ${text}\n"
        "    Log    ${text}\n"
        "Password Rule Should Be Met\n"
        "    [Arguments]    ${label}\n"
        "    Log    ${label}\n",
        encoding="utf-8",
    )
    suite = root / "reset_password_test.robot"
    content = (
        "*** Settings ***\n"
        "Resource    workflow/reset_password_workflow.robot\n"
        "*** Test Cases ***\n"
        "T\n"
        "    Reset Password Page Should Be Loaded\n"
        "    All Password Rules Should Be Unmet\n"
        "    Type New Password Progressively    abc\n"
        "    Password Rule Should Be Met    One number\n"
    )
    suite.write_text(content, encoding="utf-8")
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, str(suite), diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert not any(msg.startswith("Unknown keyword") for msg in messages), messages


@pytest.mark.asyncio
async def test_nested_resource_page_keywords_are_known(tmp_path: Path) -> None:
    service, root = await _service(tmp_path)
    (root / "pages").mkdir()
    (root / "workflow").mkdir()
    (root / "pages" / "reset_password_page.robot").write_text(
        "*** Keywords ***\n"
        "Enter New Password\n"
        "    [Arguments]    ${text}\n"
        "    No Operation\n",
        encoding="utf-8",
    )
    (root / "workflow" / "reset_password_workflow.robot").write_text(
        "*** Settings ***\n"
        "Resource    ../pages/reset_password_page.robot\n"
        "*** Keywords ***\n"
        "Type New Password Progressively\n"
        "    [Arguments]    ${text}\n"
        "    Enter New Password    ${text}\n",
        encoding="utf-8",
    )
    suite = root / "suite.robot"
    content = (
        "*** Settings ***\n"
        "Resource    workflow/reset_password_workflow.robot\n"
        "*** Test Cases ***\n"
        "T\n"
        "    Type New Password Progressively    abc\n"
        "    Enter New Password    abc\n"
    )
    suite.write_text(content, encoding="utf-8")
    diagnostics: list[dict] = []
    await service._append_semantic_diagnostics(content, str(suite), diagnostics)
    messages = [item["message"] for item in diagnostics]
    assert not any(msg.startswith("Unknown keyword") for msg in messages), messages
