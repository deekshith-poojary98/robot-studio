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
from robot_studio.infrastructure.language.robot_parsing_worker import resolve_library


class _FakeBridge:
    def __init__(self, libraries: dict[str, dict]) -> None:
        self._libraries = {key.casefold(): value for key, value in libraries.items()}

    def resolve_python(self, environment_path: Path | None) -> Path:
        assert environment_path is not None
        return environment_path / "bin" / "python"

    async def run(self, python_executable: Path, *, op: str, library: str = "", **_kwargs):
        assert op == "resolve_library"
        return self._libraries.get(
            library.casefold(),
            {"available": False, "name": library, "keywords": []},
        )


@pytest.mark.asyncio
async def test_resolve_library_worker_collections() -> None:
    result = resolve_library("Collections")
    assert result["available"] is True
    assert any(name == "Append To List" for name in result["keywords"])


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
