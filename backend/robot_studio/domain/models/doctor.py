"""Robot Doctor — Project Health Center report models."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field

from robot_studio.domain.models.analysis import (
    Finding,
    FindingCategory,
    FindingSeverity,
    FixRisk,
)
from robot_studio.domain.models.execution_knowledge import ExecutionKnowledgeSnapshot

# Re-export for Doctor consumers
__all__ = [
    "CategoryGroup",
    "DoctorHealthSummary",
    "DoctorProfile",
    "DoctorProfileId",
    "DoctorRecommendation",
    "DoctorReport",
    "DoctorReportSummary",
    "DoctorRunRequest",
    "FindingCategory",
    "FindingProviderInfo",
    "FixRisk",
    "ImprovementTrend",
]


class DoctorProfileId(str, Enum):
    QUICK = "quick"
    DEFAULT = "default"
    FULL = "full"


class FindingProviderInfo(BaseModel):
    id: str
    title: str
    description: str
    category: FindingCategory
    default_severity: FindingSeverity = FindingSeverity.WARNING
    # Quick-fix metadata defaults applied to findings from this provider
    supports_fix: bool = False
    fix_id: str | None = None
    estimated_risk: FixRisk | None = None


class DoctorProfile(BaseModel):
    id: DoctorProfileId
    title: str
    description: str
    provider_ids: list[str] = Field(default_factory=list)


class ImprovementTrend(BaseModel):
    """Delta vs previous Doctor report for the same project (if any)."""

    previous_report_id: str
    previous_total: int
    previous_critical: int
    delta_total: int
    delta_critical: int


class DoctorHealthSummary(BaseModel):
    """Project health counts — no invented percentage score."""

    total_findings: int = 0
    by_severity: dict[str, int] = Field(default_factory=dict)
    by_category: dict[str, int] = Field(default_factory=dict)
    critical_issues: int = 0  # FindingSeverity.ERROR count
    improvement_trend: ImprovementTrend | None = None


class DoctorRecommendation(BaseModel):
    rank: int
    finding_id: str
    reason: str
    finding: Finding


class CategoryGroup(BaseModel):
    category: FindingCategory
    findings: list[Finding] = Field(default_factory=list)


class DoctorReport(BaseModel):
    id: str
    project_id: str
    profile: DoctorProfileId
    created_at: datetime
    graph_version: str = ""
    incremental_revision: int = 0
    providers_run: list[str] = Field(default_factory=list)
    summary: DoctorHealthSummary = Field(default_factory=DoctorHealthSummary)
    findings: list[Finding] = Field(default_factory=list)
    grouped: list[CategoryGroup] = Field(default_factory=list)
    top_recommendations: list[DoctorRecommendation] = Field(default_factory=list)
    execution_snapshot: ExecutionKnowledgeSnapshot | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class DoctorReportSummary(BaseModel):
    """History list row — lighter than a full report."""

    id: str
    project_id: str
    profile: DoctorProfileId
    created_at: datetime
    graph_version: str = ""
    total_findings: int = 0
    critical_issues: int = 0
    providers_run: list[str] = Field(default_factory=list)


class DoctorRunRequest(BaseModel):
    profile: DoctorProfileId = DoctorProfileId.DEFAULT
    project_id: UUID | None = None
    provider_ids: list[str] | None = None  # optional override of profile set
