"""DoctorService — orchestrates FindingProviders into a Project Health report."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime
from uuid import UUID, uuid4

from robot_studio.application.services.execution_knowledge_service import (
    ExecutionKnowledgeService,
)
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.domain.interfaces.analysis import AnalysisEngine, AnalysisStore
from robot_studio.domain.interfaces.doctor import DoctorContext, FindingProvider
from robot_studio.domain.models.analysis import Finding, FindingCategory, FindingSeverity
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
from robot_studio.infrastructure.doctor.providers import (
    DEFAULT_PROVIDER_IDS,
    FULL_PROVIDER_IDS,
    QUICK_PROVIDER_IDS,
    default_finding_providers,
)
from robot_studio.infrastructure.doctor.store import SqliteDoctorStore
from robot_studio.infrastructure.repositories.project_repository import (
    SqliteProjectRepository,
)

_SEVERITY_RANK = {
    FindingSeverity.ERROR: 400,
    FindingSeverity.WARNING: 200,
    FindingSeverity.INFO: 80,
    FindingSeverity.HINT: 20,
}

_CONFIDENCE_RANK = {
    "exact": 40,
    "high": 30,
    "medium": 15,
    "low": 5,
}

_CATEGORY_ORDER = [
    FindingCategory.CORRECTNESS,
    FindingCategory.DEPENDENCIES,
    FindingCategory.EXECUTION,
    FindingCategory.PERFORMANCE,
    FindingCategory.MAINTAINABILITY,
    FindingCategory.STYLE,
]


class DoctorValidationError(Exception):
    pass


def _priority(finding: Finding) -> int:
    sev = _SEVERITY_RANK.get(finding.severity, 0)
    conf = _CONFIDENCE_RANK.get(
        finding.confidence.value if hasattr(finding.confidence, "value") else str(finding.confidence),
        0,
    )
    # Prefer fixable critical items slightly
    fix_boost = 10 if finding.supports_fix and finding.severity == FindingSeverity.ERROR else 0
    return sev + conf + fix_boost


def _recommendation_reason(finding: Finding) -> str:
    if finding.severity == FindingSeverity.ERROR:
        return "Critical correctness / dependency issue — fix before shipping."
    if finding.category == FindingCategory.EXECUTION and finding.inspection_id == "flaky_test":
        return "Unstable execution hurts trust in the suite — investigate early."
    if finding.supports_fix and finding.severity == FindingSeverity.WARNING:
        return "High-impact and marked for a future Quick Fix."
    if finding.category == FindingCategory.PERFORMANCE:
        return "High average duration; good ROI if this path is hot."
    return "Next highest priority by severity and confidence."


@dataclass
class DoctorService:
    """Orchestration + presentation layer. Does not analyze Robot sources itself."""

    context: WorkspaceContext
    analysis_engine: AnalysisEngine
    analysis_store: AnalysisStore
    store: SqliteDoctorStore
    project_repository: SqliteProjectRepository
    execution_knowledge: ExecutionKnowledgeService | None = None
    providers: list[FindingProvider] = field(default_factory=list)
    _by_id: dict[str, FindingProvider] = field(default_factory=dict, init=False)

    def __post_init__(self) -> None:
        if not self.providers:
            self.providers = default_finding_providers(self.execution_knowledge)
        self._by_id = {p.info.id: p for p in self.providers}

    def register(self, provider: FindingProvider) -> None:
        self.providers.append(provider)
        self._by_id[provider.info.id] = provider

    def list_providers(self) -> list[FindingProviderInfo]:
        return [p.info for p in self.providers]

    def list_profiles(self) -> list[DoctorProfile]:
        known = {p.info.id for p in self.providers}
        return [
            DoctorProfile(
                id=DoctorProfileId.QUICK,
                title="Quick",
                description="Correctness + dependency blockers only.",
                provider_ids=[i for i in QUICK_PROVIDER_IDS if i in known],
            ),
            DoctorProfile(
                id=DoctorProfileId.DEFAULT,
                title="Default",
                description="All static semantic inspections.",
                provider_ids=[i for i in DEFAULT_PROVIDER_IDS if i in known],
            ),
            DoctorProfile(
                id=DoctorProfileId.FULL,
                title="Full",
                description="Static inspections plus execution knowledge findings.",
                provider_ids=[i for i in FULL_PROVIDER_IDS if i in known],
            ),
        ]

    async def _resolve_project_id(self, project_id: UUID | None) -> UUID:
        if project_id is not None:
            return project_id
        active = self.context.project
        if active is None:
            raise DoctorValidationError("No active project")
        return active.id

    def _provider_ids_for(
        self,
        profile: DoctorProfileId,
        override: list[str] | None,
    ) -> list[str]:
        if override is not None:
            unknown = [i for i in override if i not in self._by_id]
            if unknown:
                raise DoctorValidationError(f"Unknown providers: {', '.join(unknown)}")
            return list(override)
        for p in self.list_profiles():
            if p.id == profile:
                return list(p.provider_ids)
        raise DoctorValidationError(f"Unknown profile: {profile}")

    async def run(
        self,
        *,
        profile: DoctorProfileId = DoctorProfileId.DEFAULT,
        project_id: UUID | None = None,
        provider_ids: list[str] | None = None,
    ) -> DoctorReport:
        pid = await self._resolve_project_id(project_id)
        ids = self._provider_ids_for(profile, provider_ids)
        gv = await self.analysis_store.get_graph_version(pid)

        ctx = DoctorContext(
            project_id=pid,
            analysis_engine=self.analysis_engine,
            analysis_store=self.analysis_store,
            execution_knowledge=self.execution_knowledge,
        )

        merged: dict[str, Finding] = {}
        ran: list[str] = []
        for provider_id in ids:
            provider = self._by_id[provider_id]
            findings = await provider.collect(ctx)
            ran.append(provider_id)
            for finding in findings:
                finding.graph_version = gv.graph_version
                finding.incremental_revision = gv.incremental_revision
                if finding.category is None:
                    finding.category = provider.info.category
                merged[finding.id] = finding

        prioritized = sorted(merged.values(), key=_priority, reverse=True)

        by_severity: dict[str, int] = defaultdict(int)
        by_category: dict[str, int] = defaultdict(int)
        for f in prioritized:
            by_severity[f.severity.value] += 1
            cat = (f.category or FindingCategory.MAINTAINABILITY).value
            by_category[cat] += 1

        critical = by_severity.get(FindingSeverity.ERROR.value, 0)

        previous = await self.store.latest_report(pid)
        trend: ImprovementTrend | None = None
        if previous is not None:
            trend = ImprovementTrend(
                previous_report_id=previous.id,
                previous_total=previous.summary.total_findings,
                previous_critical=previous.summary.critical_issues,
                delta_total=len(prioritized) - previous.summary.total_findings,
                delta_critical=critical - previous.summary.critical_issues,
            )

        grouped_map: dict[FindingCategory, list[Finding]] = defaultdict(list)
        for f in prioritized:
            grouped_map[f.category or FindingCategory.MAINTAINABILITY].append(f)
        grouped = [
            CategoryGroup(category=cat, findings=grouped_map[cat])
            for cat in _CATEGORY_ORDER
            if cat in grouped_map
        ]
        # Any unexpected categories
        for cat, items in grouped_map.items():
            if cat not in _CATEGORY_ORDER:
                grouped.append(CategoryGroup(category=cat, findings=items))

        top: list[DoctorRecommendation] = []
        for i, finding in enumerate(prioritized[:5], start=1):
            top.append(
                DoctorRecommendation(
                    rank=i,
                    finding_id=finding.id,
                    reason=_recommendation_reason(finding),
                    finding=finding,
                ),
            )

        exec_snap = None
        if self.execution_knowledge is not None:
            exec_snap = await self.execution_knowledge.snapshot(pid)

        report = DoctorReport(
            id=str(uuid4()),
            project_id=str(pid),
            profile=profile,
            created_at=datetime.now(UTC),
            graph_version=gv.graph_version,
            incremental_revision=gv.incremental_revision,
            providers_run=ran,
            summary=DoctorHealthSummary(
                total_findings=len(prioritized),
                by_severity=dict(by_severity),
                by_category=dict(by_category),
                critical_issues=critical,
                improvement_trend=trend,
            ),
            findings=prioritized,
            grouped=grouped,
            top_recommendations=top,
            execution_snapshot=exec_snap,
        )
        await self.store.save_report(report)
        return report

    async def get_report(self, report_id: str) -> DoctorReport:
        report = await self.store.get_report(report_id)
        if report is None:
            raise DoctorValidationError(f"Report not found: {report_id}")
        return report

    async def history(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 20,
    ) -> list[DoctorReportSummary]:
        pid = await self._resolve_project_id(project_id)
        return await self.store.list_history(pid, limit=limit)
