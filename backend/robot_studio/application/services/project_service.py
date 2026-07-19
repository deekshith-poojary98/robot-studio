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
from robot_studio.infrastructure.project.templates import TemplateService
from robot_studio.infrastructure.workspace.filesystem import load_manifest


class ProjectService:
    def __init__(
        self,
        repository: ProjectRepository,
        context: WorkspaceContext,
        event_bus: EventBus,
        filesystem: FilesystemProjectProvider | None = None,
        templates: TemplateService | None = None,
    ) -> None:
        self._repository = repository
        self._context = context
        self._event_bus = event_bus
        self._fs = filesystem or FilesystemProjectProvider()
        self._templates = templates or TemplateService(self._fs)

    def _require_workspace(self):
        workspace = self._context.workspace
        if workspace is None:
            raise ProjectValidationError("Open a workspace before managing projects")
        return workspace

    async def create_project(self, name: str, project_type: ProjectType) -> Project:
        workspace = self._require_workspace()
        cleaned = name.strip()
        if not cleaned:
            raise ProjectValidationError("Project name is required")
        if project_type == ProjectType.IMPORTED:
            raise ProjectValidationError(
                "Use import for existing projects",
            )

        project_root = self._fs.project_root_for_name(workspace.path, cleaned)
        self._templates.apply(project_root, cleaned, project_type)

        manifest = self._fs.create_manifest(name=cleaned, project_type=project_type)
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
            type=project_type,
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
        if not self._fs.is_robot_project(project_root):
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
            raw_path = Path(entry["path"])
            project_path = (
                raw_path
                if raw_path.is_absolute()
                else (workspace.path / raw_path).resolve()
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

    async def list_recent(self, limit: int = 10) -> list[Project]:
        recent = await self._repository.list_recent(limit=limit)
        return [project for project in recent if project.path.is_dir()]

    async def _activate(self, project: Project) -> None:
        await self._repository.record_recent(project)
        await self._context.set_active_project(project)
