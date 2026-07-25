"""Project use cases."""

from __future__ import annotations

from datetime import UTC
from pathlib import Path
from uuid import UUID

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import EventBus, ProjectCreated, ProjectImported
from robot_studio.domain.interfaces.project import ProjectRepository
from robot_studio.domain.models import Project, ProjectType
from robot_studio.infrastructure.project.filesystem import (
    FilesystemProjectProvider,
    ProjectValidationError,
)
from robot_studio.infrastructure.workspace.filesystem import load_manifest, resolve_project_entry_path


class ProjectService:
    def __init__(
        self,
        repository: ProjectRepository,
        context: WorkspaceContext,
        event_bus: EventBus,
        filesystem: FilesystemProjectProvider | None = None,
    ) -> None:
        self._repository = repository
        self._context = context
        self._event_bus = event_bus
        self._fs = filesystem or FilesystemProjectProvider()

    def _require_workspace(self):
        workspace = self._context.workspace
        if workspace is None:
            raise ProjectValidationError("Open a workspace before managing projects")
        return workspace

    async def create_project(self, name: str) -> Project:
        workspace = self._require_workspace()
        cleaned = name.strip()
        if not cleaned:
            raise ProjectValidationError("Project name is required")

        project_root = self._fs.project_root_for_name(workspace.path, cleaned)
        if project_root.exists() and any(project_root.iterdir()):
            raise ProjectValidationError(
                f"A project named '{cleaned}' already exists",
            )
        project_root.mkdir(parents=True, exist_ok=True)
        self._fs.ensure_project_dirs(project_root)

        manifest = self._fs.create_manifest(
            name=cleaned,
            project_type=ProjectType.EMPTY,
        )
        self._fs.write_manifest(project_root, manifest)
        self._fs.register_in_workspace(
            workspace.path,
            project_id=manifest.id,
            name=cleaned,
            path=project_root,
        )

        project = Project(
            id=manifest.id,
            workspace_id=workspace.id,
            name=cleaned,
            path=project_root.resolve(),
            created_at=manifest.created_at,
            type=ProjectType.EMPTY,
        )
        await self._repository.create(project)
        await self._event_bus.publish(
            ProjectCreated(workspace_id=workspace.id, project_id=project.id),
        )
        await self._activate(project)
        return project

    async def import_project(self, path: str | Path) -> Project:
        workspace = self._require_workspace()
        project_root = Path(path).expanduser().resolve()

        if not project_root.is_dir():
            raise ProjectValidationError(
                f"Directory does not exist: '{project_root}'",
            )
        if not self._fs.is_robot_project(project_root) and not self._fs.has_manifest(
            project_root,
        ):
            raise ProjectValidationError(
                f"'{project_root}' does not look like a Robot Framework project",
            )

        existing = await self._repository.get_by_path(str(project_root))
        if existing is not None and existing.workspace_id == workspace.id:
            await self._activate(existing)
            return existing

        if self._fs.has_manifest(project_root):
            manifest = self._fs.load_manifest(project_root)
            name = manifest.name
            project_id = manifest.id
            created_at = (
                manifest.created_at
                if manifest.created_at.tzinfo
                else manifest.created_at.replace(tzinfo=UTC)
            )
            project_type = (
                manifest.type
                if manifest.type != ProjectType.EMPTY
                else ProjectType.IMPORTED
            )
        else:
            name = project_root.name
            manifest = self._fs.create_manifest(
                name=name,
                project_type=ProjectType.IMPORTED,
            )
            self._fs.write_manifest(project_root, manifest)
            project_id = manifest.id
            created_at = manifest.created_at
            project_type = ProjectType.IMPORTED

        self._fs.register_in_workspace(
            workspace.path,
            project_id=project_id,
            name=name,
            path=project_root,
        )

        project = Project(
            id=project_id,
            workspace_id=workspace.id,
            name=name,
            path=project_root,
            created_at=created_at,
            type=project_type,
        )
        await self._repository.create(project)
        await self._event_bus.publish(
            ProjectImported(workspace_id=workspace.id, project_id=project.id),
        )
        await self._activate(project)
        return project

    async def list_projects(self) -> list[Project]:
        workspace = self._require_workspace()
        projects = await self._repository.list_by_workspace(workspace.id)
        # Also hydrate from workspace.json if DB is empty (fresh clone scenario)
        if projects:
            return [p for p in projects if p.path.is_dir()]

        manifest = load_manifest(workspace.path)
        hydrated: list[Project] = []
        for entry in manifest.projects:
            project_path = resolve_project_entry_path(
                workspace.path,
                str(entry.get("path", "")),
            )
            if not project_path.is_dir():
                continue
            if self._fs.has_manifest(project_path):
                pm = self._fs.load_manifest(project_path)
                project = Project(
                    id=pm.id,
                    workspace_id=workspace.id,
                    name=pm.name,
                    path=project_path,
                    created_at=pm.created_at
                    if pm.created_at.tzinfo
                    else pm.created_at.replace(tzinfo=UTC),
                    type=pm.type,
                )
            else:
                project = Project(
                    id=UUID(str(entry["id"])),
                    workspace_id=workspace.id,
                    name=str(entry.get("name", project_path.name)),
                    path=project_path,
                    created_at=workspace.created_at,
                    type=ProjectType.IMPORTED,
                )
            await self._repository.create(project)
            hydrated.append(project)
        return hydrated

    async def open_project(self, project_id: UUID) -> Project:
        workspace = self._require_workspace()
        project = await self._repository.get(project_id)
        if project is None or project.workspace_id != workspace.id:
            raise ProjectValidationError("Project not found in the active workspace")
        if not project.path.is_dir():
            raise ProjectValidationError(
                f"Project directory is missing: '{project.path}'",
            )
        await self._activate(project)
        return project

    async def open_project_at_path(self, path: str | Path) -> Project:
        """Activate a project under the open workspace from a folder/file path."""
        workspace = self._require_workspace()
        target = Path(path).expanduser().resolve()
        if target.is_file():
            target = target.parent
        if not target.is_dir():
            raise ProjectValidationError(
                f"Directory does not exist: '{target}'",
            )

        workspace_root = workspace.path.resolve()
        try:
            target.relative_to(workspace_root)
        except ValueError as exc:
            raise ProjectValidationError(
                f"'{target}' is not inside the open workspace '{workspace_root}'",
            ) from exc

        if target == workspace_root:
            projects = await self.list_projects()
            root_matches = [
                project
                for project in projects
                if project.path.resolve() == workspace_root
            ]
            if root_matches:
                await self._activate(root_matches[0])
                return root_matches[0]
            if self._fs.has_manifest(target) or self._fs.is_robot_project(target):
                return await self.import_project(target)
            raise ProjectValidationError(
                "Select a project folder (for example under Projects/), "
                "or open a Robot Framework project folder directly.",
            )

        projects = await self.list_projects()
        candidates = [
            project
            for project in projects
            if project.path.resolve() == target
            or project.path.resolve() in target.parents
        ]
        if candidates:
            pick = max(candidates, key=lambda item: len(str(item.path.resolve())))
            await self._activate(pick)
            return pick

        # Unregistered folder under the workspace — import if it looks like a project.
        cursor = target
        while cursor != workspace_root and workspace_root in cursor.parents:
            if self._fs.has_manifest(cursor) or self._fs.is_robot_project(cursor):
                return await self.import_project(cursor)
            cursor = cursor.parent

        raise ProjectValidationError(
            f"No Robot Studio project found at or above '{target}'",
        )

    async def ensure_root_project(self) -> Project:
        """Activate or register the workspace root as the sole/primary project."""
        workspace = self._require_workspace()
        projects = await self.list_projects()
        for project in projects:
            if project.path.resolve() == workspace.path.resolve():
                await self._activate(project)
                return project
        return await self.import_project(workspace.path)

    async def list_recent(self, limit: int = 10) -> list[Project]:
        recent = await self._repository.list_recent(limit=limit)
        return [project for project in recent if project.path.is_dir()]

    async def _activate(self, project: Project) -> None:
        await self._repository.record_recent(project)
        await self._context.set_active_project(project)
