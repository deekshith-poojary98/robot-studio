"""Inspection Engine — runs pluggable inspections over the Analysis Engine."""

from __future__ import annotations

from dataclasses import dataclass, field
from uuid import UUID

from robot_studio.domain.interfaces.analysis import (
    AnalysisEngine,
    AnalysisStore,
    Inspection,
    InspectionEnginePort,
)
from robot_studio.domain.models.analysis import InspectionInfo, InspectionReport
from robot_studio.infrastructure.analysis.inspections import default_inspections


@dataclass
class InspectionEngine(InspectionEnginePort):
    analysis_engine: AnalysisEngine
    store: AnalysisStore
    _inspections: dict[str, Inspection] = field(default_factory=dict, init=False)

    def __post_init__(self) -> None:
        for inspection in default_inspections():
            self.register(inspection)

    def register(self, inspection: Inspection) -> None:
        self._inspections[inspection.info.id] = inspection

    def list_inspections(self) -> list[InspectionInfo]:
        return [insp.info for insp in self._inspections.values()]

    async def run(
        self,
        project_id: UUID,
        *,
        inspection_ids: list[str] | None = None,
    ) -> InspectionReport:
        version = await self.store.get_graph_version(project_id)
        selected = inspection_ids or list(self._inspections.keys())
        findings = []
        ran: list[str] = []
        for inspection_id in selected:
            inspection = self._inspections.get(inspection_id)
            if inspection is None:
                continue
            ran.append(inspection_id)
            batch = await inspection.run(project_id, self.analysis_engine)
            for finding in batch:
                finding.graph_version = version.graph_version
                finding.incremental_revision = version.incremental_revision
                findings.append(finding)
        return InspectionReport(
            project_id=str(project_id),
            graph_version=version.graph_version,
            incremental_revision=version.incremental_revision,
            timestamp=version.timestamp,
            inspections_run=ran,
            findings=findings,
        )

    async def run_one(self, project_id: UUID, inspection_id: str) -> InspectionReport:
        if inspection_id not in self._inspections:
            raise KeyError(f"Unknown inspection: {inspection_id}")
        return await self.run(project_id, inspection_ids=[inspection_id])
