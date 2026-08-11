"""API schemas for Project Insights."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from robot_studio.domain.models.insights import InsightsSnapshot


class FileCompositionResponse(BaseModel):
    file_path: str
    counts: dict[str, int] = Field(default_factory=dict)


class RunTotalsResponse(BaseModel):
    total: int = 0
    passed: int = 0
    failed: int = 0
    cancelled: int = 0
    aborted: int = 0
    skipped_tests: int = 0
    pass_rate: float | None = None
    average_duration_ms: float | None = None


class InsightsRecentRunResponse(BaseModel):
    id: UUID
    suite: str = ""
    status: str
    started_at: datetime
    duration_ms: int | None = None
    passed: int | None = None
    failed: int | None = None
    skipped: int | None = None
    exit_code: int | None = None
    outcome: str = ""


class FileRunStatsResponse(BaseModel):
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


class InsightsResponse(BaseModel):
    composition: dict[str, int] = Field(default_factory=dict)
    composition_files: list[FileCompositionResponse] = Field(default_factory=list)
    runs: RunTotalsResponse = Field(default_factory=RunTotalsResponse)
    recent_runs: list[InsightsRecentRunResponse] = Field(default_factory=list)
    run_files: list[FileRunStatsResponse] = Field(default_factory=list)
    index_state: str = "idle"
    index_message: str = ""


def to_insights_response(snapshot: InsightsSnapshot) -> InsightsResponse:
    return InsightsResponse(
        composition=dict(snapshot.composition_totals),
        composition_files=[
            FileCompositionResponse(file_path=item.file_path, counts=dict(item.counts))
            for item in snapshot.composition_files
        ],
        runs=RunTotalsResponse(
            total=snapshot.run_totals.total,
            passed=snapshot.run_totals.passed,
            failed=snapshot.run_totals.failed,
            cancelled=snapshot.run_totals.cancelled,
            aborted=snapshot.run_totals.aborted,
            skipped_tests=snapshot.run_totals.skipped_tests,
            pass_rate=snapshot.run_totals.pass_rate,
            average_duration_ms=snapshot.run_totals.average_duration_ms,
        ),
        recent_runs=[
            InsightsRecentRunResponse(
                id=run.id,
                suite=run.suite,
                status=run.status.value,
                started_at=run.started_at,
                duration_ms=run.duration_ms,
                passed=run.passed,
                failed=run.failed,
                skipped=run.skipped,
                exit_code=run.exit_code,
                outcome=run.outcome,
            )
            for run in snapshot.recent_runs
        ],
        run_files=[
            FileRunStatsResponse(
                file_path=item.file_path,
                runs=item.runs,
                passed=item.passed,
                failed=item.failed,
                cancelled=item.cancelled,
                aborted=item.aborted,
                last_outcome=item.last_outcome,
                last_started_at=item.last_started_at,
                last_run_id=item.last_run_id,
                last_failed_run_id=item.last_failed_run_id,
            )
            for item in snapshot.run_files
        ],
        index_state=snapshot.index_state,
        index_message=snapshot.index_message,
    )
