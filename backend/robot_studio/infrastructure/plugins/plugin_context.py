"""Controlled API surface exposed to plugins."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from robot_studio.application.services.environment_service import EnvironmentService
from robot_studio.application.services.execution_service import ExecutionService
from robot_studio.application.services.language_service import LanguageFacade
from robot_studio.application.services.project_service import ProjectService
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.config import Settings
from robot_studio.core.events import DomainEvent, EventBus
from robot_studio.domain.models import Environment, Project, Workspace
from robot_studio.infrastructure.plugins.plugin_storage import PluginStorage


@dataclass
class PluginContext:
    """Facade passed to plugin lifecycle hooks — no direct Container access."""

    plugin_id: str
    workspace_context: WorkspaceContext
    event_bus: EventBus
    storage: PluginStorage
    logger: logging.Logger
    settings: Settings
    project_service: ProjectService
    environment_service: EnvironmentService
    execution_service: ExecutionService
    language_facade: LanguageFacade

    @property
    def workspace(self) -> Workspace | None:
        return self.workspace_context.workspace

    @property
    def project(self) -> Project | None:
        return self.workspace_context.project

    @property
    def environment(self) -> Environment | None:
        return self.workspace_context.environment

    async def list_projects(self) -> list[Project]:
        workspace = self.workspace
        if workspace is None:
            return []
        return await self.project_service.list_projects()

    async def list_environments(self) -> list[Environment]:
        workspace = self.workspace
        if workspace is None:
            return []
        return await self.environment_service.list_environments()

    async def list_executions(self, *, limit: int = 50) -> list[Any]:
        return await self.execution_service.list_history(limit=limit)

    async def current_execution(self) -> Any:
        return await self.execution_service.get_status()

    async def language_definition(self, **kwargs: Any) -> dict | None:
        return await self.language_facade.definition(**kwargs)

    async def publish(self, event: DomainEvent) -> None:
        await self.event_bus.publish(event)
