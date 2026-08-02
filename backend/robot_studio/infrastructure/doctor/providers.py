"""Built-in FindingProviders for Robot Doctor.

Static providers adapt existing ``Inspection`` classes (no duplicated analysis).
Execution providers consume ``ExecutionKnowledgeService`` only.
"""

from __future__ import annotations

import hashlib
from typing import TYPE_CHECKING

from robot_studio.domain.interfaces.analysis import Inspection
from robot_studio.domain.interfaces.doctor import DoctorContext, FindingProvider
from robot_studio.domain.models.analysis import (
    BindingConfidence,
    Finding,
    FindingCategory,
    FindingSeverity,
    FixRisk,
)
from robot_studio.domain.models.doctor import FindingProviderInfo
from robot_studio.infrastructure.analysis.inspections import (
    CircularDependencyInspection,
    DuplicateKeywordInspection,
    LargeKeywordInspection,
    MissingImportInspection,
    UnusedKeywordInspection,
    UnusedResourceInspection,
)

if TYPE_CHECKING:
    from robot_studio.application.services.execution_knowledge_service import (
        ExecutionKnowledgeService,
    )


def _fid(provider_id: str, *parts: str) -> str:
    raw = "|".join([provider_id, *parts])
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:20]


def _enrich(
    finding: Finding,
    *,
    info: FindingProviderInfo,
    rationale: str,
) -> Finding:
    data = finding.model_dump()
    data["category"] = info.category
    data["rationale"] = rationale or finding.rationale
    data["supports_fix"] = info.supports_fix
    data["fix_id"] = info.fix_id
    data["estimated_risk"] = info.estimated_risk
    # Keep inspection_id aligned with provider id for Doctor grouping
    data["inspection_id"] = info.id
    return Finding.model_validate(data)


class InspectionFindingProvider(FindingProvider):
    """Adapts an Inspection into a FindingProvider (Doctor never calls Inspections)."""

    def __init__(
        self,
        inspection: Inspection,
        *,
        category: FindingCategory,
        rationale: str,
        supports_fix: bool = False,
        fix_id: str | None = None,
        estimated_risk: FixRisk | None = None,
    ) -> None:
        self._inspection = inspection
        self._rationale = rationale
        self._info = FindingProviderInfo(
            id=inspection.info.id,
            title=inspection.info.title,
            description=inspection.info.description,
            category=category,
            default_severity=inspection.info.default_severity,
            supports_fix=supports_fix,
            fix_id=fix_id,
            estimated_risk=estimated_risk,
        )

    @property
    def info(self) -> FindingProviderInfo:
        return self._info

    async def collect(self, ctx: DoctorContext) -> list[Finding]:
        raw = await self._inspection.run(ctx.project_id, ctx.analysis_engine)
        return [
            _enrich(f, info=self._info, rationale=self._rationale)
            for f in raw
        ]


class FlakyTestProvider(FindingProvider):
    def __init__(self, knowledge: ExecutionKnowledgeService | None = None) -> None:
        self._knowledge = knowledge

    @property
    def info(self) -> FindingProviderInfo:
        return FindingProviderInfo(
            id="flaky_test",
            title="Flaky test candidate",
            description="Tests with alternating or intermittent pass/fail history.",
            category=FindingCategory.EXECUTION,
            default_severity=FindingSeverity.WARNING,
            supports_fix=False,
            fix_id=None,
            estimated_risk=FixRisk.HIGH,
        )

    async def collect(self, ctx: DoctorContext) -> list[Finding]:
        knowledge = self._knowledge or ctx.execution_knowledge
        if knowledge is None:
            return []
        findings: list[Finding] = []
        candidates = await knowledge.flaky_candidates(ctx.project_id, limit=50)
        for cand in candidates:
            entity = cand.entity
            reasons = ", ".join(cand.reasons) if cand.reasons else "unstable history"
            findings.append(
                Finding(
                    id=_fid(self.info.id, entity.id),
                    inspection_id=self.info.id,
                    severity=FindingSeverity.WARNING,
                    message=f"Flaky candidate '{entity.name}' ({reasons})",
                    confidence=cand.confidence,
                    category=self.info.category,
                    rationale=(
                        "Execution history shows inconsistent outcomes "
                        "(alternating, intermittent failures, or duration variance)."
                    ),
                    supports_fix=False,
                    fix_id=None,
                    estimated_risk=FixRisk.HIGH,
                    entity=entity,
                    file_path=entity.file_path,
                    line=entity.line,
                    column=entity.column,
                    metadata={
                        "fail_rate": cand.fail_rate,
                        "execution_count": cand.execution_count,
                        "reasons": cand.reasons,
                        **cand.metadata,
                    },
                ),
            )
        return findings


class SlowKeywordProvider(FindingProvider):
    def __init__(
        self,
        knowledge: ExecutionKnowledgeService | None = None,
        *,
        min_average_ms: float = 500.0,
        limit: int = 25,
    ) -> None:
        self._knowledge = knowledge
        self._min_average_ms = min_average_ms
        self._limit = limit

    @property
    def info(self) -> FindingProviderInfo:
        return FindingProviderInfo(
            id="slow_keyword",
            title="Slow keyword",
            description="Keywords with high average execution duration.",
            category=FindingCategory.PERFORMANCE,
            default_severity=FindingSeverity.INFO,
            supports_fix=False,
            fix_id=None,
            estimated_risk=FixRisk.MEDIUM,
        )

    async def collect(self, ctx: DoctorContext) -> list[Finding]:
        knowledge = self._knowledge or ctx.execution_knowledge
        if knowledge is None:
            return []
        findings: list[Finding] = []
        slow = await knowledge.slowest_keywords(ctx.project_id, limit=self._limit)
        for item in slow:
            if item.average_duration_ms < self._min_average_ms:
                continue
            entity = item.entity
            findings.append(
                Finding(
                    id=_fid(self.info.id, entity.id),
                    inspection_id=self.info.id,
                    severity=FindingSeverity.INFO,
                    message=(
                        f"Keyword '{entity.name}' averages "
                        f"{item.average_duration_ms:.0f}ms over {item.execution_count} runs"
                    ),
                    confidence=BindingConfidence.HIGH,
                    category=self.info.category,
                    rationale=(
                        "Execution knowledge ranks this keyword among the slowest "
                        f"(threshold {self._min_average_ms:.0f}ms average)."
                    ),
                    supports_fix=False,
                    estimated_risk=FixRisk.MEDIUM,
                    entity=entity,
                    file_path=entity.file_path,
                    line=entity.line,
                    column=entity.column,
                    metadata={
                        "average_duration_ms": item.average_duration_ms,
                        "total_duration_ms": item.total_duration_ms,
                        "execution_count": item.execution_count,
                        "threshold_ms": self._min_average_ms,
                    },
                ),
            )
        return findings


class NeverExecutedKeywordProvider(FindingProvider):
    def __init__(self, knowledge: ExecutionKnowledgeService | None = None) -> None:
        self._knowledge = knowledge

    @property
    def info(self) -> FindingProviderInfo:
        return FindingProviderInfo(
            id="never_executed_keyword",
            title="Never executed keyword",
            description="User keywords present in the graph but never seen in linked runs.",
            category=FindingCategory.EXECUTION,
            default_severity=FindingSeverity.HINT,
            supports_fix=False,
            fix_id="review_never_executed_keyword",
            estimated_risk=FixRisk.LOW,
        )

    async def collect(self, ctx: DoctorContext) -> list[Finding]:
        knowledge = self._knowledge or ctx.execution_knowledge
        if knowledge is None:
            return []
        # Only report when at least one run has been linked — otherwise everything is "never"
        snap = await knowledge.snapshot(ctx.project_id)
        if snap.linked_runs == 0:
            return []
        findings: list[Finding] = []
        entities = await knowledge.never_executed_keywords(ctx.project_id)
        for entity in entities:
            findings.append(
                Finding(
                    id=_fid(self.info.id, entity.id),
                    inspection_id=self.info.id,
                    severity=FindingSeverity.HINT,
                    message=f"Keyword '{entity.name}' has never executed in linked runs",
                    confidence=BindingConfidence.MEDIUM,
                    category=self.info.category,
                    rationale=(
                        "Semantic graph contains this keyword, but no linked "
                        "output.xml run has executed it."
                    ),
                    supports_fix=False,
                    fix_id=self.info.fix_id,
                    estimated_risk=FixRisk.LOW,
                    entity=entity,
                    file_path=entity.file_path,
                    line=entity.line,
                    column=entity.column,
                ),
            )
        return findings


def static_finding_providers() -> list[FindingProvider]:
    return [
        InspectionFindingProvider(
            UnusedKeywordInspection(),
            category=FindingCategory.MAINTAINABILITY,
            rationale=(
                "No bound callers exist in the semantic call graph for this keyword."
            ),
            supports_fix=True,
            fix_id="remove_unused_keyword",
            estimated_risk=FixRisk.MEDIUM,
        ),
        InspectionFindingProvider(
            UnusedResourceInspection(),
            category=FindingCategory.MAINTAINABILITY,
            rationale="No suite or resource imports this resource file.",
            supports_fix=True,
            fix_id="remove_unused_resource",
            estimated_risk=FixRisk.MEDIUM,
        ),
        InspectionFindingProvider(
            DuplicateKeywordInspection(),
            category=FindingCategory.CORRECTNESS,
            rationale=(
                "Multiple keyword definitions share the same normalized name, "
                "which can bind ambiguously at runtime."
            ),
            supports_fix=False,
            fix_id="resolve_duplicate_keyword",
            estimated_risk=FixRisk.HIGH,
        ),
        InspectionFindingProvider(
            MissingImportInspection(),
            category=FindingCategory.DEPENDENCIES,
            rationale="A Resource or Variables import path could not be resolved on disk.",
            supports_fix=True,
            fix_id="fix_missing_import",
            estimated_risk=FixRisk.MEDIUM,
        ),
        InspectionFindingProvider(
            CircularDependencyInspection(),
            category=FindingCategory.DEPENDENCIES,
            rationale="A cycle exists in the resource/suite import graph.",
            supports_fix=False,
            fix_id="break_circular_dependency",
            estimated_risk=FixRisk.HIGH,
        ),
        InspectionFindingProvider(
            LargeKeywordInspection(),
            category=FindingCategory.MAINTAINABILITY,
            rationale=(
                "Keyword has many outgoing calls — a candidate for extract-keyword."
            ),
            supports_fix=False,
            fix_id="extract_keyword",
            estimated_risk=FixRisk.LOW,
        ),
    ]


def execution_finding_providers(
    knowledge: ExecutionKnowledgeService | None = None,
) -> list[FindingProvider]:
    return [
        FlakyTestProvider(knowledge),
        SlowKeywordProvider(knowledge),
        NeverExecutedKeywordProvider(knowledge),
    ]


def default_finding_providers(
    knowledge: ExecutionKnowledgeService | None = None,
) -> list[FindingProvider]:
    return [*static_finding_providers(), *execution_finding_providers(knowledge)]


# Profile → provider id sets
QUICK_PROVIDER_IDS = (
    "missing_import",
    "circular_dependency",
    "duplicate_keyword",
)
DEFAULT_PROVIDER_IDS = tuple(p.info.id for p in static_finding_providers())
FULL_PROVIDER_IDS = tuple(p.info.id for p in default_finding_providers())
