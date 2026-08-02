"""REST schemas for Analysis Engine + Inspection Engine."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from robot_studio.domain.models.analysis import (
    AnalysisSnapshot,
    DependencyNode,
    EdgeRef,
    EntityRef,
    Finding,
    FindingSeverity,
    InspectionInfo,
    InspectionReport,
    UsageStat,
)


class AnalysisSnapshotResponse(BaseModel):
    project_id: str
    graph_version: str = "0"
    incremental_revision: int = 0
    epoch: int = 0
    timestamp: datetime | None = None
    entity_count: int = 0
    edge_count: int = 0
    unbound_calls: int = 0

    @classmethod
    def from_model(cls, snap: AnalysisSnapshot) -> AnalysisSnapshotResponse:
        return cls(**snap.model_dump())


class EntityRefResponse(BaseModel):
    id: str
    kind: str
    name: str
    file_path: str
    line: int = 1
    column: int = 1
    documentation: str = ""
    detail: str = ""

    @classmethod
    def from_model(cls, entity: EntityRef) -> EntityRefResponse:
        return cls(**entity.model_dump())


class EdgeRefResponse(BaseModel):
    edge_kind: str
    source: EntityRefResponse | None = None
    target: EntityRefResponse | None = None
    source_file: str = ""
    source_line: int = 1
    source_column: int = 1
    target_name: str = ""
    confidence: str = "low"
    context: str = ""

    @classmethod
    def from_model(cls, edge: EdgeRef) -> EdgeRefResponse:
        data = edge.model_dump()
        if data.get("source"):
            data["source"] = EntityRefResponse(**data["source"])
        if data.get("target"):
            data["target"] = EntityRefResponse(**data["target"])
        return cls(**data)


class DependencyNodeResponse(BaseModel):
    id: str
    kind: str
    name: str
    file_path: str
    imports: list[str] = Field(default_factory=list)
    imported_by: list[str] = Field(default_factory=list)

    @classmethod
    def from_model(cls, node: DependencyNode) -> DependencyNodeResponse:
        return cls(**node.model_dump())


class UsageStatResponse(BaseModel):
    entity: EntityRefResponse
    callers: int = 0
    callees: int = 0
    low_confidence_refs: int = 0

    @classmethod
    def from_model(cls, stat: UsageStat) -> UsageStatResponse:
        return cls(
            entity=EntityRefResponse.from_model(stat.entity),
            callers=stat.callers,
            callees=stat.callees,
            low_confidence_refs=stat.low_confidence_refs,
        )


class FindingResponse(BaseModel):
    id: str
    inspection_id: str
    severity: FindingSeverity
    message: str
    confidence: str
    category: str | None = None
    rationale: str = ""
    supports_fix: bool = False
    fix_id: str | None = None
    estimated_risk: str | None = None
    entity: EntityRefResponse | None = None
    secondary_entities: list[EntityRefResponse] = Field(default_factory=list)
    file_path: str = ""
    line: int = 1
    column: int = 1
    related_edges: list[EdgeRefResponse] = Field(default_factory=list)
    metadata: dict = Field(default_factory=dict)
    graph_version: str = ""
    incremental_revision: int = 0

    @classmethod
    def from_model(cls, finding: Finding) -> FindingResponse:
        return cls(
            id=finding.id,
            inspection_id=finding.inspection_id,
            severity=finding.severity,
            message=finding.message,
            confidence=finding.confidence.value,
            category=finding.category.value if finding.category else None,
            rationale=finding.rationale,
            supports_fix=finding.supports_fix,
            fix_id=finding.fix_id,
            estimated_risk=(
                finding.estimated_risk.value if finding.estimated_risk else None
            ),
            entity=EntityRefResponse.from_model(finding.entity) if finding.entity else None,
            secondary_entities=[
                EntityRefResponse.from_model(e) for e in finding.secondary_entities
            ],
            file_path=finding.file_path,
            line=finding.line,
            column=finding.column,
            related_edges=[EdgeRefResponse.from_model(e) for e in finding.related_edges],
            metadata=finding.metadata,
            graph_version=finding.graph_version,
            incremental_revision=finding.incremental_revision,
        )


class InspectionInfoResponse(BaseModel):
    id: str
    title: str
    description: str
    default_severity: FindingSeverity = FindingSeverity.WARNING

    @classmethod
    def from_model(cls, info: InspectionInfo) -> InspectionInfoResponse:
        return cls(**info.model_dump())


class InspectionListResponse(BaseModel):
    inspections: list[InspectionInfoResponse] = Field(default_factory=list)


class InspectRequest(BaseModel):
    inspection_ids: list[str] | None = None
    project_id: str | None = None


class InspectionReportResponse(BaseModel):
    project_id: str
    graph_version: str
    incremental_revision: int
    timestamp: datetime | None = None
    inspections_run: list[str] = Field(default_factory=list)
    findings: list[FindingResponse] = Field(default_factory=list)

    @classmethod
    def from_model(cls, report: InspectionReport) -> InspectionReportResponse:
        return cls(
            project_id=report.project_id,
            graph_version=report.graph_version,
            incremental_revision=report.incremental_revision,
            timestamp=report.timestamp,
            inspections_run=report.inspections_run,
            findings=[FindingResponse.from_model(f) for f in report.findings],
        )


class EntityListResponse(BaseModel):
    items: list[EntityRefResponse] = Field(default_factory=list)


class EdgeListResponse(BaseModel):
    items: list[EdgeRefResponse] = Field(default_factory=list)


class DependencyGraphResponse(BaseModel):
    nodes: list[DependencyNodeResponse] = Field(default_factory=list)


class UsageStatsResponse(BaseModel):
    items: list[UsageStatResponse] = Field(default_factory=list)


class AffectedTestsRequest(BaseModel):
    changed_files: list[str] = Field(default_factory=list)
    changed_symbols: list[str] = Field(default_factory=list)
    project_id: str | None = None
