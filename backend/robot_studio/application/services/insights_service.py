"""Project Insights — index composition + execution health aggregates."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.domain.interfaces.indexing import IndexStore
from robot_studio.domain.models import ExecutionRun, ExecutionStatus
from robot_studio.domain.models.insights import (
    FileComposition,
    FileRunStats,
    InsightsRecentRun,
    InsightsSnapshot,
    RunOutcomeTotals,
)
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
)


class InsightsValidationError(Exception):
    """Raised when insights cannot be computed."""


_FILE_SUFFIXES = {".robot", ".resource", ".py", ".yaml", ".yml"}


def _run_outcome(run: ExecutionRun) -> str:
    if run.status == ExecutionStatus.CANCELLED:
        return "CANCELLED"
    if run.status == ExecutionStatus.ABORTED:
        return "ABORTED"
    if run.status == ExecutionStatus.FAILED or (run.failed or 0) > 0 or (
        run.exit_code is not None and run.exit_code != 0
    ):
        return "FAIL"
    if run.status == ExecutionStatus.FINISHED:
        return "PASS"
    return run.status.value.upper()


def _file_suite_key(suite: str) -> str | None:
    """Map a run's suite label to a real source file, or None if not file-scoped.

    Project/tag/selection runs store display labels like ``Project: Demo`` in
    ``suite`` — those must not appear as rows in the per-file Insights table.
    """
    text = (suite or "").strip()
    if not text:
        return None
    lower = text.lower()
    if lower.startswith(("project: ", "tag: ")) or lower.startswith("selected ("):
        return None
    # "login.robot :: Test Name" → attribute to the file basename/path.
    if " :: " in text:
        text = text.split(" :: ", 1)[0].strip()
        if not text:
            return None
    path = Path(text)
    if path.suffix.lower() not in _FILE_SUFFIXES:
        return None
    return str(path)


@dataclass
class InsightsService:
    context: WorkspaceContext
    index_store: IndexStore
    execution_repository: SqliteExecutionRepository

    async def get_snapshot(self, *, recent_limit: int = 20) -> InsightsSnapshot:
        workspace = self.context.workspace
        if workspace is None:
            raise InsightsValidationError("Open a workspace before viewing insights")

        totals = await self.index_store.composition_by_kind(workspace.id)
        raw_files = await self.index_store.composition_by_file(workspace.id)
        composition_files = [
            FileComposition(file_path=item["file_path"], counts=dict(item["counts"]))
            for item in raw_files
        ]

        runs = await self.execution_repository.list_by_workspace(
            workspace.id,
            limit=500,
        )
        run_totals, recent, file_stats = _aggregate_runs(
            runs,
            recent_limit=recent_limit,
        )

        index_status = await self.index_store.status(workspace.id)
        return InsightsSnapshot(
            composition_totals=totals,
            composition_files=composition_files,
            run_totals=run_totals,
            recent_runs=recent,
            run_files=file_stats,
            index_message="",
            index_state="ready" if index_status.get("symbols_indexed") else "idle",
        )


def _aggregate_runs(
    runs: list[ExecutionRun],
    *,
    recent_limit: int,
) -> tuple[RunOutcomeTotals, list[InsightsRecentRun], list[FileRunStats]]:
    passed = failed = cancelled = aborted = 0
    skipped_tests = 0
    durations: list[int] = []
    recent: list[InsightsRecentRun] = []
    by_file: dict[str, dict] = defaultdict(
        lambda: {
            "runs": 0,
            "passed": 0,
            "failed": 0,
            "cancelled": 0,
            "aborted": 0,
            "last_outcome": None,
            "last_started_at": None,
        }
    )

    for run in runs:
        outcome = _run_outcome(run)
        if outcome == "PASS":
            passed += 1
        elif outcome == "FAIL":
            failed += 1
        elif outcome == "CANCELLED":
            cancelled += 1
        elif outcome == "ABORTED":
            aborted += 1

        skipped_tests += int(run.skipped or 0)
        if run.duration_ms is not None:
            durations.append(int(run.duration_ms))

        if len(recent) < recent_limit:
            recent.append(
                InsightsRecentRun(
                    id=run.id,
                    suite=run.suite,
                    status=run.status,
                    started_at=run.started_at,
                    duration_ms=run.duration_ms,
                    passed=run.passed,
                    failed=run.failed,
                    skipped=run.skipped,
                    exit_code=run.exit_code,
                    outcome=outcome,
                )
            )

        path = _file_suite_key(run.suite)
        if not path:
            continue
        bucket = by_file[path]
        bucket["runs"] += 1
        if outcome == "PASS":
            bucket["passed"] += 1
        elif outcome == "FAIL":
            bucket["failed"] += 1
        elif outcome == "CANCELLED":
            bucket["cancelled"] += 1
        elif outcome == "ABORTED":
            bucket["aborted"] += 1
        last_at: datetime | None = bucket["last_started_at"]
        if last_at is None or run.started_at > last_at:
            bucket["last_started_at"] = run.started_at
            bucket["last_outcome"] = outcome

    counted = passed + failed + cancelled + aborted
    pass_rate = (passed / counted * 100.0) if counted else None
    avg_duration = (sum(durations) / len(durations)) if durations else None

    file_stats = [
        FileRunStats(
            file_path=path,
            runs=int(data["runs"]),
            passed=int(data["passed"]),
            failed=int(data["failed"]),
            cancelled=int(data["cancelled"]),
            aborted=int(data["aborted"]),
            last_outcome=data["last_outcome"],
            last_started_at=data["last_started_at"],
        )
        for path, data in by_file.items()
    ]
    file_stats.sort(key=lambda item: (-item.failed, -item.runs, item.file_path))

    return (
        RunOutcomeTotals(
            total=counted,
            passed=passed,
            failed=failed,
            cancelled=cancelled,
            aborted=aborted,
            skipped_tests=skipped_tests,
            pass_rate=pass_rate,
            average_duration_ms=avg_duration,
        ),
        recent,
        file_stats,
    )
