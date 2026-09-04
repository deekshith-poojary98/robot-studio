"""Unit tests for plain-text Find in Files (content search)."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest
from robot_studio.application.services.content_search_service import (
    ContentSearchService,
)
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import InMemoryEventBus
from robot_studio.domain.models import (
    Project,
    ProjectType,
    Workspace,
    WorkspaceSettings,
)


@pytest.fixture
async def content_search(tmp_path: Path):
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    root = tmp_path / "Demo"
    root.mkdir()
    (root / "tests").mkdir()
    (root / "tests" / "login.robot").write_text(
        "*** Test Cases ***\nLogin Happy Path\n    Log    login ok\n",
        encoding="utf-8",
    )
    (root / "resources").mkdir()
    (root / "resources" / "auth.resource").write_text(
        "*** Keywords ***\nLogin\n    Log    do login\n",
        encoding="utf-8",
    )
    (root / ".venv").mkdir()
    (root / ".venv" / "noise.robot").write_text(
        "*** Test Cases ***\nShouldNotMatch\n    Log    login\n",
        encoding="utf-8",
    )

    workspace = Workspace(
        id=uuid4(),
        name="Demo",
        path=root,
        created_at=datetime.now(UTC),
        settings=WorkspaceSettings(),
    )
    project = Project(
        id=workspace.id,
        workspace_id=workspace.id,
        name="Demo",
        path=root,
        created_at=datetime.now(UTC),
        type=ProjectType.EMPTY,
    )
    await context.open(workspace)
    await context.set_active_project(project)
    service = ContentSearchService(context=context, index_store=None)
    return service, root


@pytest.mark.asyncio
async def test_content_search_finds_matches_grouped_by_file(content_search) -> None:
    service, _root = content_search
    result = await service.search_content("login")
    assert result.query == "login"
    assert result.files_scanned >= 2
    paths = {Path(item.path).name for item in result.files}
    assert "login.robot" in paths
    assert "auth.resource" in paths
    # .venv pruned
    assert "noise.robot" not in paths
    for file_hits in result.files:
        assert file_hits.match_count == len(file_hits.matches)
        for match in file_hits.matches:
            assert "login" in match.text.lower()
            assert match.line >= 1
            assert match.column >= 1


@pytest.mark.asyncio
async def test_content_search_cancel(content_search) -> None:
    service, _root = content_search
    cancelled = {"done": False}

    def cancel_check() -> bool:
        if cancelled["done"]:
            return True
        cancelled["done"] = True
        return False

    result = await service.search_content("login", cancel_check=cancel_check)
    assert result.truncated is True


@pytest.mark.asyncio
async def test_content_search_requires_project(tmp_path: Path) -> None:
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    service = ContentSearchService(context=context)
    with pytest.raises(Exception, match="Open a project"):
        await service.search_content("x")
