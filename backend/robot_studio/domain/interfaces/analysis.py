"""Ports for the Robot Analysis Engine + Inspection Engine."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from uuid import UUID

from robot_studio.domain.models.analysis import (
    DependencyNode,
    EdgeRef,
    EntityRef,
    Finding,
    GraphVersion,
    InspectionInfo,
    InspectionReport,
    SemanticEdge,
    SemanticEntity,
    UsageStat,
)


class AnalysisStore(ABC):
    @abstractmethod
    async def initialize(self) -> None: ...

    @abstractmethod
    async def bump_revision(
        self,
        project_id: UUID,
        *,
        new_graph_version: bool = False,
    ) -> GraphVersion: ...

    @abstractmethod
    async def get_graph_version(self, project_id: UUID) -> GraphVersion: ...

    @abstractmethod
    async def get_epoch(self, project_id: UUID | None = None) -> int: ...

    @abstractmethod
    async def clear_file(self, file_path: Path) -> None: ...

    @abstractmethod
    async def clear_project(self, project_id: UUID) -> None: ...

    @abstractmethod
    async def upsert_entities(self, entities: list[SemanticEntity], *, epoch: int) -> None: ...

    @abstractmethod
    async def upsert_edges(self, edges: list[SemanticEdge], *, epoch: int) -> None: ...

    @abstractmethod
    async def replace_file_graph(
        self,
        file_path: Path,
        entities: list[SemanticEntity],
        edges: list[SemanticEdge],
        *,
        epoch: int,
    ) -> None: ...

    @abstractmethod
    async def list_entities(
        self,
        *,
        project_id: UUID | None = None,
        kind: str | None = None,
        name_normalized: str | None = None,
    ) -> list[SemanticEntity]: ...

    @abstractmethod
    async def get_entity(self, entity_id: str) -> SemanticEntity | None: ...

    @abstractmethod
    async def find_entities_by_normalized_name(
        self,
        name_normalized: str,
        *,
        project_id: UUID | None = None,
        kinds: list[str] | None = None,
    ) -> list[SemanticEntity]: ...

    @abstractmethod
    async def list_edges(
        self,
        *,
        project_id: UUID | None = None,
        edge_kind: str | None = None,
        source_id: str | None = None,
        target_id: str | None = None,
        unbound_only: bool = False,
    ) -> list[SemanticEdge]: ...

    @abstractmethod
    async def update_edge_binding(
        self,
        edge_id: int,
        *,
        target_id: str | None,
        confidence: str,
    ) -> None: ...

    @abstractmethod
    async def get_cache(self, cache_key: str) -> str | None: ...

    @abstractmethod
    async def set_cache(self, cache_key: str, payload: str, *, epoch: int, project_id: str) -> None: ...

    @abstractmethod
    async def invalidate_cache(self, project_id: UUID | None = None) -> None: ...


class AnalysisEngine(ABC):
    """Queryable semantic engine — graph queries for Impact / Rename / AI."""

    @abstractmethod
    async def find_unused_keywords(self, project_id: UUID) -> list[EntityRef]: ...

    @abstractmethod
    async def find_unused_resources(self, project_id: UUID) -> list[EntityRef]: ...

    @abstractmethod
    async def find_duplicate_keywords(self, project_id: UUID) -> list[list[EntityRef]]: ...

    @abstractmethod
    async def find_missing_imports(self, project_id: UUID) -> list[EdgeRef]: ...

    @abstractmethod
    async def find_keyword_callers(self, project_id: UUID, keyword: str) -> list[EdgeRef]: ...

    @abstractmethod
    async def find_keyword_callees(self, project_id: UUID, keyword: str) -> list[EdgeRef]: ...

    @abstractmethod
    async def dependency_graph(self, project_id: UUID) -> list[DependencyNode]: ...

    @abstractmethod
    async def affected_tests(
        self,
        project_id: UUID,
        *,
        changed_files: list[str] | None = None,
        changed_symbols: list[str] | None = None,
    ) -> list[EntityRef]: ...

    @abstractmethod
    async def variable_references(self, project_id: UUID, variable: str) -> list[EdgeRef]: ...

    @abstractmethod
    async def library_usage(self, project_id: UUID, library: str | None = None) -> list[EdgeRef]: ...

    @abstractmethod
    async def keyword_usage_statistics(self, project_id: UUID) -> list[UsageStat]: ...


class Inspection(ABC):
    """Pluggable Doctor-facing check. Always returns ``Finding`` rows."""

    @property
    @abstractmethod
    def info(self) -> InspectionInfo: ...

    @abstractmethod
    async def run(self, project_id: UUID, engine: AnalysisEngine) -> list[Finding]: ...


class InspectionEnginePort(ABC):
    @abstractmethod
    def list_inspections(self) -> list[InspectionInfo]: ...

    @abstractmethod
    async def run(
        self,
        project_id: UUID,
        *,
        inspection_ids: list[str] | None = None,
    ) -> InspectionReport: ...

    @abstractmethod
    async def run_one(self, project_id: UUID, inspection_id: str) -> InspectionReport: ...
