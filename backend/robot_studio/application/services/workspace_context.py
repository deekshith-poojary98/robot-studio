"""Tracks the active workspace, project, and environment session."""

from uuid import UUID

from robot_studio.core.events import (
    EventBus,
    ProjectOpened,
    WorkspaceClosed,
    WorkspaceOpened,
)
from robot_studio.domain.models import Environment, Project, Workspace


class WorkspaceContext:
    """Holds the currently open workspace/project/environment for the backend process."""

    def __init__(self, event_bus: EventBus) -> None:
        self._event_bus = event_bus
        self._workspace: Workspace | None = None
        self._project: Project | None = None
        self._environment: Environment | None = None

    @property
    def workspace(self) -> Workspace | None:
        return self._workspace

    @property
    def workspace_id(self) -> UUID | None:
        return self._workspace.id if self._workspace else None

    @property
    def project(self) -> Project | None:
        return self._project

    @property
    def project_id(self) -> UUID | None:
        return self._project.id if self._project else None

    @property
    def environment(self) -> Environment | None:
        return self._environment

    @property
    def environment_id(self) -> UUID | None:
        return self._environment.id if self._environment else None

    @property
    def is_open(self) -> bool:
        return self._workspace is not None

    async def open(self, workspace: Workspace) -> None:
        if self._workspace is not None:
            await self.close()
        self._workspace = workspace
        self._project = None
        self._environment = None
        await self._event_bus.publish(WorkspaceOpened(workspace_id=workspace.id))

    def replace_workspace(self, workspace: Workspace) -> None:
        """Update the in-memory workspace snapshot without emitting open/close."""
        if self._workspace is None:
            raise RuntimeError("Cannot replace workspace without an open workspace")
        if workspace.id != self._workspace.id:
            raise RuntimeError("Replacement workspace id does not match the open workspace")
        self._workspace = workspace

    async def set_active_project(self, project: Project) -> None:
        if self._workspace is None:
            raise RuntimeError("Cannot set active project without an open workspace")
        if project.workspace_id != self._workspace.id:
            raise RuntimeError("Project does not belong to the active workspace")
        self._project = project
        await self._event_bus.publish(
            ProjectOpened(
                workspace_id=self._workspace.id,
                project_id=project.id,
            ),
        )

    async def clear_active_project(self) -> None:
        self._project = None

    async def set_active_environment(self, environment: Environment) -> None:
        if self._workspace is None:
            raise RuntimeError("Cannot set active environment without an open workspace")
        if environment.workspace_id != self._workspace.id:
            raise RuntimeError("Environment does not belong to the active workspace")
        self._environment = environment

    async def clear_active_environment(self) -> None:
        self._environment = None

    async def close(self) -> None:
        if self._workspace is None:
            return
        workspace_id = self._workspace.id
        self._workspace = None
        self._project = None
        self._environment = None
        await self._event_bus.publish(WorkspaceClosed(workspace_id=workspace_id))
