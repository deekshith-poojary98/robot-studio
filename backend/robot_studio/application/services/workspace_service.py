"""Workspace use cases."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid5

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.domain.interfaces.workspace import WorkspaceRepository
from robot_studio.domain.models import Workspace
from robot_studio.infrastructure.workspace.filesystem import (
    WorkspaceValidationError,
    create_workspace_structure,
    is_workspace,
    load_manifest,
)

# Stable namespace for deriving workspace IDs from absolute paths.
WORKSPACE_ID_NAMESPACE = UUID("7f3c1e2a-9b4d-4c6e-a1f0-8d2e5b7c9a10")


class WorkspaceService:
    def __init__(
        self,
        repository: WorkspaceRepository,
        context: WorkspaceContext,
    ) -> None:
        self._repository = repository
        self._context = context

    @staticmethod
    def workspace_id_for_path(path: Path) -> UUID:
        return uuid5(WORKSPACE_ID_NAMESPACE, str(path.resolve()))

    async def create_workspace(self, name: str, location: str | Path) -> Workspace:
        cleaned_name = name.strip()
        if not cleaned_name:
            raise WorkspaceValidationError("Workspace name is required")

        parent = Path(location).expanduser().resolve()
        if not parent.is_dir():
            raise WorkspaceValidationError(
                f"Location does not exist or is not a directory: '{parent}'",
            )

        workspace_root = parent / cleaned_name
        manifest = create_workspace_structure(workspace_root, cleaned_name)

        workspace = Workspace(
            id=self.workspace_id_for_path(workspace_root),
            name=manifest.name,
            path=workspace_root,
            created_at=manifest.created_at,
        )

        await self._repository.create(workspace)
        await self._activate(workspace)
        return workspace

    async def open_workspace(self, path: str | Path) -> Workspace:
        workspace_root = Path(path).expanduser().resolve()

        if not workspace_root.is_dir():
            raise WorkspaceValidationError(
                f"Directory does not exist: '{workspace_root}'",
            )
        if not is_workspace(workspace_root):
            raise WorkspaceValidationError(
                f"'{workspace_root}' is not a Robot Studio workspace "
                "(missing .robotstudio/workspace.json)",
            )

        manifest = load_manifest(workspace_root)
        workspace = Workspace(
            id=self.workspace_id_for_path(workspace_root),
            name=manifest.name,
            path=workspace_root,
            created_at=manifest.created_at
            if manifest.created_at.tzinfo
            else manifest.created_at.replace(tzinfo=UTC),
        )

        await self._repository.create(workspace)
        await self._activate(workspace)
        return workspace

    async def list_recent(self, limit: int = 10) -> list[Workspace]:
        recent = await self._repository.list_recent(limit=limit)
        valid: list[Workspace] = []
        for workspace in recent:
            if is_workspace(workspace.path):
                valid.append(workspace)
        return valid

    async def get_active(self) -> Workspace | None:
        return self._context.workspace

    async def _activate(self, workspace: Workspace) -> None:
        await self._repository.record_recent(workspace)
        await self._context.open(workspace)
