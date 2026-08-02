"""REST schemas for /analysis/execution/* knowledge APIs."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from robot_studio.api.schemas.analysis import EntityRefResponse
from robot_studio.domain.models.execution_knowledge import (
    EntityExecutionStats,
    ExecutionHistoryEntry,
    ExecutionKnowledgeSnapshot,
    FlakyCandidate,
    HeatMapEntry,
    LinkedRunInfo,
    SlowEntity,
)


class ExecutionKnowledgeSnapshotResponse(BaseModel):
    project_id: str
    linked_runs: int = 0
    entities_with_stats: int = 0
    execution_edges: int = 0

    @classmethod
    def from_model(cls, snap: ExecutionKnowledgeSnapshot) -> ExecutionKnowledgeSnapshotResponse:
        return cls(**snap.model_dump())


class LinkedRunResponse(BaseModel):
    run_id: str
    project_id: str
    graph_version: str
    incremental_revision: int = 0
    linked_at: datetime
    test_count: int = 0
    keyword_steps: int = 0

    @classmethod
    def from_model(cls, info: LinkedRunInfo) -> LinkedRunResponse:
        return cls(**info.model_dump())


class ExecutionHistoryItemResponse(BaseModel):
    run_id: str
    entity_id: str
    entity: EntityRefResponse | None = None
    status: str
    duration_ms: float = 0.0
    role: str = "subject"
    executed_at: datetime | None = None
    message: str = ""
    graph_version: str = ""
    confidence: str = "high"

    @classmethod
    def from_model(cls, entry: ExecutionHistoryEntry) -> ExecutionHistoryItemResponse:
        return cls(
            run_id=entry.run_id,
            entity_id=entry.entity_id,
            entity=EntityRefResponse.from_model(entry.entity) if entry.entity else None,
            status=entry.status,
            duration_ms=entry.duration_ms,
            role=entry.role,
            executed_at=entry.executed_at,
            message=entry.message,
            graph_version=entry.graph_version,
            confidence=entry.confidence.value,
        )


class ExecutionHistoryListResponse(BaseModel):
    items: list[ExecutionHistoryItemResponse] = Field(default_factory=list)


class SlowEntityResponse(BaseModel):
    entity: EntityRefResponse
    average_duration_ms: float
    total_duration_ms: float
    execution_count: int

    @classmethod
    def from_model(cls, item: SlowEntity) -> SlowEntityResponse:
        return cls(
            entity=EntityRefResponse.from_model(item.entity),
            average_duration_ms=item.average_duration_ms,
            total_duration_ms=item.total_duration_ms,
            execution_count=item.execution_count,
        )


class SlowListResponse(BaseModel):
    items: list[SlowEntityResponse] = Field(default_factory=list)


class EntityStatsResponse(BaseModel):
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

    @classmethod
    def from_model(cls, stats: EntityExecutionStats) -> EntityStatsResponse:
        return cls(**stats.model_dump())


class EntityStatsListResponse(BaseModel):
    items: list[EntityStatsResponse] = Field(default_factory=list)


class HeatMapListResponse(BaseModel):
    items: list[dict] = Field(default_factory=list)

    @classmethod
    def from_models(cls, items: list[HeatMapEntry]) -> HeatMapListResponse:
        return cls(
            items=[
                {
                    "entity": EntityRefResponse.from_model(h.entity).model_dump(),
                    "execution_count": h.execution_count,
                    "fail_count": h.fail_count,
                    "fail_rate": h.fail_rate,
                    "heat_score": h.heat_score,
                    "average_duration_ms": h.average_duration_ms,
                    "last_failure": h.last_failure.isoformat() if h.last_failure else None,
                }
                for h in items
            ],
        )


class FlakyListResponse(BaseModel):
    items: list[dict] = Field(default_factory=list)

    @classmethod
    def from_models(cls, items: list[FlakyCandidate]) -> FlakyListResponse:
        return cls(
            items=[
                {
                    "entity": EntityRefResponse.from_model(f.entity).model_dump(),
                    "confidence": f.confidence.value,
                    "reasons": f.reasons,
                    "fail_rate": f.fail_rate,
                    "execution_count": f.execution_count,
                    "alternating_score": f.alternating_score,
                    "duration_cv": f.duration_cv,
                    "metadata": f.metadata,
                }
                for f in items
            ],
        )


class NeverExecutedResponse(BaseModel):
    items: list[EntityRefResponse] = Field(default_factory=list)
