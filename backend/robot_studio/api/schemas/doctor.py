"""REST schemas for Robot Doctor (/doctor/*)."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field

from robot_studio.api.schemas.analysis import FindingResponse
from robot_studio.api.schemas.execution_knowledge import ExecutionKnowledgeSnapshotResponse
from robot_studio.domain.models.doctor import (
    CategoryGroup,
    DoctorHealthSummary,
    DoctorProfile,
    DoctorProfileId,
    DoctorRecommendation,
    DoctorReport,
    DoctorReportSummary,
    FindingProviderInfo,
    ImprovementTrend,
)


class DoctorProfileResponse(BaseModel):
    id: str
    title: str
    description: str
    provider_ids: list[str] = Field(default_factory=list)

    @classmethod
    def from_model(cls, profile: DoctorProfile) -> DoctorProfileResponse:
        return cls(
            id=profile.id.value,
            title=profile.title,
            description=profile.description,
            provider_ids=list(profile.provider_ids),
        )


class FindingProviderInfoResponse(BaseModel):
    id: str
    title: str
    description: str
    category: str
    default_severity: str
    supports_fix: bool = False
    fix_id: str | None = None
    estimated_risk: str | None = None

    @classmethod
    def from_model(cls, info: FindingProviderInfo) -> FindingProviderInfoResponse:
        return cls(
            id=info.id,
            title=info.title,
            description=info.description,
            category=info.category.value,
            default_severity=info.default_severity.value,
            supports_fix=info.supports_fix,
            fix_id=info.fix_id,
            estimated_risk=info.estimated_risk.value if info.estimated_risk else None,
        )


class DoctorProfilesResponse(BaseModel):
    profiles: list[DoctorProfileResponse] = Field(default_factory=list)
    providers: list[FindingProviderInfoResponse] = Field(default_factory=list)


class DoctorRunRequestBody(BaseModel):
    profile: DoctorProfileId = DoctorProfileId.DEFAULT
    project_id: str | None = None
    provider_ids: list[str] | None = None


class ImprovementTrendResponse(BaseModel):
    previous_report_id: str
    previous_total: int
    previous_critical: int
    delta_total: int
    delta_critical: int

    @classmethod
    def from_model(cls, trend: ImprovementTrend) -> ImprovementTrendResponse:
        return cls(**trend.model_dump())


class DoctorHealthSummaryResponse(BaseModel):
    total_findings: int = 0
    by_severity: dict[str, int] = Field(default_factory=dict)
    by_category: dict[str, int] = Field(default_factory=dict)
    critical_issues: int = 0
    improvement_trend: ImprovementTrendResponse | None = None

    @classmethod
    def from_model(cls, summary: DoctorHealthSummary) -> DoctorHealthSummaryResponse:
        return cls(
            total_findings=summary.total_findings,
            by_severity=dict(summary.by_severity),
            by_category=dict(summary.by_category),
            critical_issues=summary.critical_issues,
            improvement_trend=(
                ImprovementTrendResponse.from_model(summary.improvement_trend)
                if summary.improvement_trend
                else None
            ),
        )


class DoctorRecommendationResponse(BaseModel):
    rank: int
    finding_id: str
    reason: str
    finding: FindingResponse

    @classmethod
    def from_model(cls, rec: DoctorRecommendation) -> DoctorRecommendationResponse:
        return cls(
            rank=rec.rank,
            finding_id=rec.finding_id,
            reason=rec.reason,
            finding=FindingResponse.from_model(rec.finding),
        )


class CategoryGroupResponse(BaseModel):
    category: str
    findings: list[FindingResponse] = Field(default_factory=list)

    @classmethod
    def from_model(cls, group: CategoryGroup) -> CategoryGroupResponse:
        return cls(
            category=group.category.value,
            findings=[FindingResponse.from_model(f) for f in group.findings],
        )


class DoctorReportResponse(BaseModel):
    id: str
    project_id: str
    profile: str
    created_at: datetime
    graph_version: str = ""
    incremental_revision: int = 0
    providers_run: list[str] = Field(default_factory=list)
    summary: DoctorHealthSummaryResponse
    findings: list[FindingResponse] = Field(default_factory=list)
    grouped: list[CategoryGroupResponse] = Field(default_factory=list)
    top_recommendations: list[DoctorRecommendationResponse] = Field(default_factory=list)
    execution_snapshot: ExecutionKnowledgeSnapshotResponse | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    @classmethod
    def from_model(cls, report: DoctorReport) -> DoctorReportResponse:
        return cls(
            id=report.id,
            project_id=report.project_id,
            profile=report.profile.value,
            created_at=report.created_at,
            graph_version=report.graph_version,
            incremental_revision=report.incremental_revision,
            providers_run=list(report.providers_run),
            summary=DoctorHealthSummaryResponse.from_model(report.summary),
            findings=[FindingResponse.from_model(f) for f in report.findings],
            grouped=[CategoryGroupResponse.from_model(g) for g in report.grouped],
            top_recommendations=[
                DoctorRecommendationResponse.from_model(r)
                for r in report.top_recommendations
            ],
            execution_snapshot=(
                ExecutionKnowledgeSnapshotResponse.from_model(report.execution_snapshot)
                if report.execution_snapshot
                else None
            ),
            metadata=dict(report.metadata),
        )


class DoctorReportSummaryResponse(BaseModel):
    id: str
    project_id: str
    profile: str
    created_at: datetime
    graph_version: str = ""
    total_findings: int = 0
    critical_issues: int = 0
    providers_run: list[str] = Field(default_factory=list)

    @classmethod
    def from_model(cls, row: DoctorReportSummary) -> DoctorReportSummaryResponse:
        return cls(
            id=row.id,
            project_id=row.project_id,
            profile=row.profile.value,
            created_at=row.created_at,
            graph_version=row.graph_version,
            total_findings=row.total_findings,
            critical_issues=row.critical_issues,
            providers_run=list(row.providers_run),
        )


class DoctorHistoryResponse(BaseModel):
    items: list[DoctorReportSummaryResponse] = Field(default_factory=list)
