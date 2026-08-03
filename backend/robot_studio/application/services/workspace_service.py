"""Workspace use cases."""

from __future__ import annotations

from datetime import UTC
from pathlib import Path
from uuid import UUID, uuid4

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.domain.interfaces.workspace import WorkspaceRepository
from robot_studio.domain.models import Workspace
from robot_studio.infrastructure.workspace.filesystem import (
    WorkspaceManifest,
    WorkspaceValidationError,
    create_workspace_structure,
    initialize_project_as_workspace,
    is_classic_workspace,
    is_workspace,
    load_manifest,
    read_project_manifest_id,
    write_manifest,
)


class WorkspaceService:
    def __init__(
        self,
        repository: WorkspaceRepository,
        context: WorkspaceContext,
    ) -> None:
        self._repository = repository
        self._context = context

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
        workspace_id = uuid4()
        manifest = create_workspace_structure(
            workspace_root,
            cleaned_name,
            workspace_id=workspace_id,
        )
        assert manifest.id is not None

        workspace = Workspace(
            id=manifest.id,
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
        workspace_id, manifest = self._ensure_durable_id(workspace_root, manifest)
        created_at = (
            manifest.created_at
            if manifest.created_at.tzinfo
            else manifest.created_at.replace(tzinfo=UTC)
        )
        workspace = Workspace(
            id=workspace_id,
            name=manifest.name,
            path=workspace_root,
            created_at=created_at,
        )

        await self._repository.create(workspace)
        await self._activate(workspace)
        return workspace

    async def open_or_init_project_workspace(
        self,
        path: str | Path,
        name: str | None = None,
    ) -> Workspace:
        """Open a folder as a workspace, initializing in-project metadata if needed."""
        workspace_root = Path(path).expanduser().resolve()
        if not workspace_root.is_dir():
            raise WorkspaceValidationError(
                f"Directory does not exist: '{workspace_root}'",
            )
        if not is_workspace(workspace_root):
            # Prefer an existing project.json id so standalone stays one UUID.
            existing_project_id = read_project_manifest_id(workspace_root)
            initialize_project_as_workspace(
                workspace_root,
                name,
                workspace_id=existing_project_id or uuid4(),
            )
        return await self.open_workspace(workspace_root)

    async def list_recent(self, limit: int = 10) -> list[Workspace]:
        recent = await self._repository.list_recent(limit=limit)
        valid: list[Workspace] = []
        for workspace in recent:
            # Only classic multi-project containers — project-folder opens belong
            # on the Recent Projects list.
            if is_classic_workspace(workspace.path):
                valid.append(workspace)
        return valid

    async def get_active(self) -> Workspace | None:
        return self._context.workspace

    def _ensure_durable_id(
        self,
        workspace_root: Path,
        manifest: WorkspaceManifest,
    ) -> tuple[UUID, WorkspaceManifest]:
        """Migrate-on-read: persist a durable id when the manifest lacks one."""
        if manifest.id is not None:
            return manifest.id, manifest

        if not is_classic_workspace(workspace_root):
            project_id = read_project_manifest_id(workspace_root)
            workspace_id = project_id or uuid4()
        else:
            workspace_id = uuid4()

        updated = manifest.with_id(workspace_id)
        write_manifest(workspace_root, updated)
        return workspace_id, updated

    async def _activate(self, workspace: Workspace) -> None:
        if is_classic_workspace(workspace.path):
            await self._repository.record_recent(workspace)
        await self._context.open(workspace)
