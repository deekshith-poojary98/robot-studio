"""Execution knowledge models — links runs to the semantic graph."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field

from robot_studio.domain.models.analysis import BindingConfidence, EntityRef


class ExecutionEdgeKind(str, Enum):
    EXECUTED_KEYWORD = "executed_keyword"  # test/kw → keyword
    FAILED_KEYWORD = "failed_keyword"  # test → failed keyword
    SUITE_EXECUTION = "suite_execution"  # suite → run
    EXECUTION_GRAPH = "execution_graph"  # run → graph_version


class EntityExecutionStats(BaseModel):
    entity_id: str
    project_id: str
    execution_count: int = 0
    pass_count: int = 0
    fail_count: int = 0
    skipped_count: int = 0
    average_duration_ms: float = 0.0
    total_duration_ms: float = 0.0
    last_execution: datetime | None = None
    last_failure: datetime | None = None
    first_seen: datetime | None = None
    last_seen: datetime | None = None


class ExecutionHistoryEntry(BaseModel):
    run_id: str
    entity_id: str
    entity: EntityRef | None = None
    status: str
    duration_ms: float = 0.0
    role: str = "subject"  # subject | callee | failed
    executed_at: datetime | None = None
    message: str = ""
    graph_version: str = ""
    confidence: BindingConfidence = BindingConfidence.HIGH


class ExecutionEdgeRef(BaseModel):
    edge_kind: ExecutionEdgeKind
    source_id: str
    target_id: str | None = None
    run_id: str
    target_name: str = ""
    status: str = ""
    duration_ms: float = 0.0
    confidence: BindingConfidence = BindingConfidence.HIGH
    graph_version: str = ""


class LinkedRunInfo(BaseModel):
    run_id: str
    project_id: str
    graph_version: str
    incremental_revision: int = 0
    linked_at: datetime
    test_count: int = 0
    keyword_steps: int = 0


class HeatMapEntry(BaseModel):
    entity: EntityRef
    execution_count: int = 0
    fail_count: int = 0
    fail_rate: float = 0.0
    heat_score: float = 0.0
    average_duration_ms: float = 0.0
    last_failure: datetime | None = None


class FlakyCandidate(BaseModel):
    entity: EntityRef
    confidence: BindingConfidence
    reasons: list[str] = Field(default_factory=list)
    fail_rate: float = 0.0
    execution_count: int = 0
    alternating_score: float = 0.0
    duration_cv: float = 0.0
    metadata: dict[str, Any] = Field(default_factory=dict)


class SlowEntity(BaseModel):
    entity: EntityRef
    average_duration_ms: float
    total_duration_ms: float
    execution_count: int


class ExecutionKnowledgeSnapshot(BaseModel):
    project_id: str
    linked_runs: int = 0
    entities_with_stats: int = 0
    execution_edges: int = 0


class RunTestFailure(BaseModel):
    """Failed test from a single run — Jump-to-Source + re-run payload."""

    run_id: str
    name: str
    message: str = ""
    source: str = ""
    line: int | None = None
    column: int | None = None
    entity_id: str | None = None
    duration_ms: float = 0.0
    status: str = "FAIL"
