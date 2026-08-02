"""Semantic analysis domain models (Robot Analysis Engine)."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field


class EntityKind(str, Enum):
    KEYWORD = "keyword"
    TEST_CASE = "test_case"
    VARIABLE = "variable"
    RESOURCE = "resource"
    LIBRARY = "library"
    SUITE = "suite"
    TAG = "tag"
    FILE = "file"


class EdgeKind(str, Enum):
    CALLS = "calls"
    IMPORTS_RESOURCE = "imports_resource"
    IMPORTS_LIBRARY = "imports_library"
    IMPORTS_VARIABLES = "imports_variables"
    REFERENCES_VARIABLE = "references_variable"
    TAGGED = "tagged"
    CONTAINS = "contains"  # suite/file contains test/keyword


class BindingConfidence(str, Enum):
    """First-class confidence for every bound/unbound relationship.

    Safe Rename / Safe Delete should refuse ``LOW`` (and typically unbound) refs.
    """

    EXACT = "exact"  # identical name / path resolve
    HIGH = "high"  # RF-normalized / alias / embedded match
    MEDIUM = "medium"  # plausible but weaker (e.g. BDD strip only)
    LOW = "low"  # heuristic, ambiguous, or unresolved


class FindingSeverity(str, Enum):
    ERROR = "error"
    WARNING = "warning"
    INFO = "info"
    HINT = "hint"


class FindingCategory(str, Enum):
    """Doctor grouping — set by FindingProviders (not inventable by the UI)."""

    CORRECTNESS = "correctness"
    MAINTAINABILITY = "maintainability"
    PERFORMANCE = "performance"
    DEPENDENCIES = "dependencies"
    EXECUTION = "execution"
    STYLE = "style"


class FixRisk(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class SemanticEntity(BaseModel):
    id: str
    kind: EntityKind
    name: str
    name_normalized: str
    file_path: Path
    line: int = 1
    column: int = 1
    documentation: str = ""
    detail: str = ""
    project_id: UUID | None = None
    workspace_id: UUID | None = None
    qualified_name: str = ""


class SemanticEdge(BaseModel):
    id: int | None = None
    edge_kind: EdgeKind
    source_id: str
    target_id: str | None = None
    source_file: Path
    source_line: int = 1
    source_column: int = 1
    target_name: str = ""
    target_name_normalized: str = ""
    confidence: BindingConfidence = BindingConfidence.LOW
    project_id: UUID | None = None
    context: str = ""


class EntityRef(BaseModel):
    id: str
    kind: str
    name: str
    file_path: str
    line: int = 1
    column: int = 1
    documentation: str = ""
    detail: str = ""


class EdgeRef(BaseModel):
    edge_kind: str
    source: EntityRef | None = None
    target: EntityRef | None = None
    source_file: str = ""
    source_line: int = 1
    source_column: int = 1
    target_name: str = ""
    confidence: str = BindingConfidence.LOW.value
    context: str = ""


class DependencyNode(BaseModel):
    id: str
    kind: str
    name: str
    file_path: str
    imports: list[str] = Field(default_factory=list)
    imported_by: list[str] = Field(default_factory=list)


class UsageStat(BaseModel):
    entity: EntityRef
    callers: int = 0
    callees: int = 0
    low_confidence_refs: int = 0


class GraphVersion(BaseModel):
    """Version identity for a project's semantic graph.

    ``graph_version`` changes on full rebuild; ``incremental_revision`` bumps on
    every file ingest / rebind. Replay / AI / Impact can pin both.
    """

    project_id: str
    graph_version: str
    incremental_revision: int = 0
    timestamp: datetime
    epoch: int = 0  # alias of incremental_revision for cache keys


class AnalysisSnapshot(BaseModel):
    project_id: str
    graph_version: str = "0"
    incremental_revision: int = 0
    epoch: int = 0
    timestamp: datetime | None = None
    entity_count: int = 0
    edge_count: int = 0
    unbound_calls: int = 0


class Finding(BaseModel):
    """Uniform inspection result — Doctor and future UIs consume only this shape."""

    id: str
    inspection_id: str
    severity: FindingSeverity
    message: str
    confidence: BindingConfidence = BindingConfidence.HIGH
    category: FindingCategory | None = None
    rationale: str = ""  # "Why is this reported?"
    supports_fix: bool = False
    fix_id: str | None = None
    estimated_risk: FixRisk | None = None
    entity: EntityRef | None = None
    secondary_entities: list[EntityRef] = Field(default_factory=list)
    file_path: str = ""
    line: int = 1
    column: int = 1
    related_edges: list[EdgeRef] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)
    graph_version: str = ""
    incremental_revision: int = 0


class InspectionInfo(BaseModel):
    id: str
    title: str
    description: str
    default_severity: FindingSeverity = FindingSeverity.WARNING
    category: FindingCategory | None = None


class InspectionReport(BaseModel):
    project_id: str
    graph_version: str
    incremental_revision: int
    timestamp: datetime | None = None
    inspections_run: list[str] = Field(default_factory=list)
    findings: list[Finding] = Field(default_factory=list)
