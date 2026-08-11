"""Built-in FindingProviders for Robot Doctor.

Doctor owns **structural project health** only:
circular imports, duplicate keywords, potentially unused keywords/resources.

Missing imports stay in Problems / live diagnostics.
Execution smells (flaky / slow / never-executed) stay out of Doctor —
Insights / Reports own run health.
Large-keyword heuristics are not Doctor surface for beta.
"""

from __future__ import annotations

from robot_studio.domain.interfaces.analysis import Inspection
from robot_studio.domain.interfaces.doctor import DoctorContext, FindingProvider
from robot_studio.domain.models.analysis import Finding, FindingCategory, FixRisk
from robot_studio.domain.models.doctor import FindingProviderInfo
from robot_studio.infrastructure.analysis.inspections import (
    CircularDependencyInspection,
    DuplicateKeywordInspection,
    UnusedKeywordInspection,
    UnusedResourceInspection,
)


def _enrich(
    finding: Finding,
    *,
    info: FindingProviderInfo,
    rationale: str,
) -> Finding:
    data = finding.model_dump()
    data["category"] = info.category
    data["rationale"] = rationale or finding.rationale
    data["supports_fix"] = False  # Doctor never pretends Quick Fix exists
    data["fix_id"] = None
    data["estimated_risk"] = info.estimated_risk
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
            supports_fix=False,
            fix_id=None,
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


def structural_finding_providers() -> list[FindingProvider]:
    """The only providers Robot Doctor runs."""
    return [
        InspectionFindingProvider(
            CircularDependencyInspection(),
            category=FindingCategory.DEPENDENCIES,
            rationale=(
                "These resources or suites import each other in a cycle. "
                "Robot may fail to resolve imports or load files in a surprising order. "
                "Break the cycle by moving shared keywords into a third resource "
                "that both sides import."
            ),
            estimated_risk=FixRisk.HIGH,
        ),
        InspectionFindingProvider(
            DuplicateKeywordInspection(),
            category=FindingCategory.CORRECTNESS,
            rationale=(
                "Multiple definitions share the same keyword name. "
                "At runtime Robot may call a different definition than you expect. "
                "Rename one definition or delete the duplicate."
            ),
            estimated_risk=FixRisk.HIGH,
        ),
        InspectionFindingProvider(
            UnusedKeywordInspection(),
            category=FindingCategory.MAINTAINABILITY,
            rationale=(
                "No static callers were found in the project call graph. "
                "This can be a false positive for shared library resources, "
                "dynamic keyword names, or keywords reserved for future suites. "
                "Confirm before deleting."
            ),
            estimated_risk=FixRisk.LOW,
        ),
        InspectionFindingProvider(
            UnusedResourceInspection(),
            category=FindingCategory.MAINTAINABILITY,
            rationale=(
                "No suite or resource imports this file in the static import graph. "
                "It may still be loaded dynamically or kept intentionally. "
                "Confirm before deleting."
            ),
            estimated_risk=FixRisk.LOW,
        ),
    ]


def default_finding_providers(knowledge: object | None = None) -> list[FindingProvider]:
    """Doctor provider set. ``knowledge`` kept for call-site compatibility."""
    _ = knowledge
    return structural_finding_providers()


# Single structural scan — Quick / Full aliases map here for API compatibility.
STRUCTURAL_PROVIDER_IDS = tuple(p.info.id for p in structural_finding_providers())
QUICK_PROVIDER_IDS = STRUCTURAL_PROVIDER_IDS
DEFAULT_PROVIDER_IDS = STRUCTURAL_PROVIDER_IDS
FULL_PROVIDER_IDS = STRUCTURAL_PROVIDER_IDS
