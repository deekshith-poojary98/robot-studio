"""FindingProvider port — Doctor orchestrates these; it does not analyze."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from uuid import UUID

from robot_studio.domain.interfaces.analysis import AnalysisEngine, AnalysisStore
from robot_studio.domain.models.analysis import Finding
from robot_studio.domain.models.doctor import FindingProviderInfo


@dataclass
class DoctorContext:
    """Shared inputs for FindingProviders. Providers never own Doctor state."""

    project_id: UUID
    analysis_engine: AnalysisEngine
    analysis_store: AnalysisStore
    # Optional — execution providers no-op gracefully when absent / empty
    execution_knowledge: object | None = None


class FindingProvider(ABC):
    """Produces ``Finding`` rows for Doctor. One concern per provider."""

    @property
    @abstractmethod
    def info(self) -> FindingProviderInfo: ...

    @abstractmethod
    async def collect(self, ctx: DoctorContext) -> list[Finding]: ...
