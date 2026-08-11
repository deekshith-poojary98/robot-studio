"""Project Insights snapshot — index composition + run health."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from robot_studio.domain.models import ExecutionStatus


class CompositionTotals(BaseModel):
    totals: dict[str, int] = Field(default_factory=dict)


class FileComposition(BaseModel):
    file_path: str
    counts: dict[str, int] = Field(default_factory=dict)


class RunOutcomeTotals(BaseModel):
    total: int = 0
    passed: int = 0
    failed: int = 0
    cancelled: int = 0
    aborted: int = 0
    skipped_tests: int = 0
    pass_rate: float | None = None
    average_duration_ms: float | None = None


class InsightsRecentRun(BaseModel):
    id: UUID
    suite: str = ""
    status: ExecutionStatus
    started_at: datetime
    duration_ms: int | None = None
    passed: int | None = None
    failed: int | None = None
    skipped: int | None = None
    exit_code: int | None = None
    outcome: str = ""


class FileRunStats(BaseModel):
    file_path: str
    runs: int = 0
    passed: int = 0
    failed: int = 0
    cancelled: int = 0
    aborted: int = 0
    last_outcome: str | None = None
    last_started_at: datetime | None = None
    last_run_id: UUID | None = None
    last_failed_run_id: UUID | None = None


class InsightsSnapshot(BaseModel):
    composition_totals: dict[str, int] = Field(default_factory=dict)
    composition_files: list[FileComposition] = Field(default_factory=list)
    run_totals: RunOutcomeTotals = Field(default_factory=RunOutcomeTotals)
    recent_runs: list[InsightsRecentRun] = Field(default_factory=list)
    run_files: list[FileRunStats] = Field(default_factory=list)
    index_message: str = ""
    index_state: str = "idle"
