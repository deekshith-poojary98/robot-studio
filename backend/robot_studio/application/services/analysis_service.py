"""Application façade for Analysis Engine + Inspection Engine."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from uuid import UUID

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.domain.models.analysis import (
    AnalysisSnapshot,
    DependencyNode,
    EdgeRef,
    EntityRef,
    InspectionInfo,
    InspectionReport,
    UsageStat,
)
from robot_studio.infrastructure.analysis.engine import RobotAnalysisEngine
from robot_studio.infrastructure.analysis.inspections_engine import InspectionEngine
from robot_studio.infrastructure.repositories.project_repository import (
    SqliteProjectRepository,
)


class AnalysisValidationError(Exception):
    """Raised when analysis cannot run (no project context, etc.)."""


@dataclass
class AnalysisService:
    context: WorkspaceContext
    engine: RobotAnalysisEngine
    inspection_engine: InspectionEngine
    project_repository: SqliteProjectRepository

    async def _require_project(self, project_id: UUID | None = None) -> UUID:
        if project_id is not None:
            return project_id
        project = self.context.project
        if project is None:
            raise AnalysisValidationError("No active project — open a project first")
        return project.id

    async def snapshot(self, project_id: UUID | None = None) -> AnalysisSnapshot:
        pid = await self._require_project(project_id)
        return await self.engine.snapshot(pid)

    async def rebuild(self, project_id: UUID | None = None) -> AnalysisSnapshot:
        pid = await self._require_project(project_id)
        project = await self.project_repository.get(pid)
        if project is None:
            raise AnalysisValidationError(f"Unknown project: {pid}")
        workspace_id = self.context.workspace.id if self.context.workspace else None
        return await self.engine.rebuild_project(
            pid,
            workspace_id=workspace_id,
            roots=[Path(project.path)],
        )

    def list_inspections(self) -> list[InspectionInfo]:
        return self.inspection_engine.list_inspections()

    async def inspect(
        self,
        *,
        inspection_ids: list[str] | None = None,
        project_id: UUID | None = None,
    ) -> InspectionReport:
        return await self.inspection_engine.run(
            await self._require_project(project_id),
            inspection_ids=inspection_ids,
        )

    async def inspect_one(
        self,
        inspection_id: str,
        project_id: UUID | None = None,
    ) -> InspectionReport:
        try:
            return await self.inspection_engine.run_one(
                await self._require_project(project_id),
                inspection_id,
            )
        except KeyError as exc:
            raise AnalysisValidationError(str(exc)) from exc

    # --- Graph query API (not inspections) ---

    async def find_keyword_callers(
        self,
        keyword: str,
        project_id: UUID | None = None,
    ) -> list[EdgeRef]:
        return await self.engine.find_keyword_callers(
            await self._require_project(project_id),
            keyword,
        )

    async def find_keyword_callees(
        self,
        keyword: str,
        project_id: UUID | None = None,
    ) -> list[EdgeRef]:
        return await self.engine.find_keyword_callees(
            await self._require_project(project_id),
            keyword,
        )

    async def dependency_graph(self, project_id: UUID | None = None) -> list[DependencyNode]:
        return await self.engine.dependency_graph(await self._require_project(project_id))

    async def affected_tests(
        self,
        *,
        changed_files: list[str] | None = None,
        changed_symbols: list[str] | None = None,
        project_id: UUID | None = None,
    ) -> list[EntityRef]:
        return await self.engine.affected_tests(
            await self._require_project(project_id),
            changed_files=changed_files,
            changed_symbols=changed_symbols,
        )

    async def variable_references(
        self,
        variable: str,
        project_id: UUID | None = None,
    ) -> list[EdgeRef]:
        return await self.engine.variable_references(
            await self._require_project(project_id),
            variable,
        )

    async def library_usage(
        self,
        library: str | None = None,
        project_id: UUID | None = None,
    ) -> list[EdgeRef]:
        return await self.engine.library_usage(
            await self._require_project(project_id),
            library,
        )

    async def keyword_usage_statistics(
        self,
        project_id: UUID | None = None,
    ) -> list[UsageStat]:
        return await self.engine.keyword_usage_statistics(
            await self._require_project(project_id),
        )
