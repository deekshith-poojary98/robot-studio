"""Project Insights — index composition + execution health aggregates."""

from __future__ import annotations

import asyncio
import logging
import time
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.domain.interfaces.indexing import IndexStore
from robot_studio.domain.models import ExecutionRun
from robot_studio.domain.models.insights import (
    FileComposition,
    FileRunStats,
    InsightsRecentRun,
    InsightsSnapshot,
    RunOutcomeTotals,
)
from robot_studio.infrastructure.execution.output_stats import (
    load_or_build_file_outcomes,
)
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
)

logger = logging.getLogger(__name__)


class InsightsValidationError(Exception):
    """Raised when insights cannot be computed."""


_FILE_SUFFIXES = {".robot", ".resource", ".py", ".yaml", ".yml"}


def _run_outcome(run: ExecutionRun) -> str:
    return run.result_badge()


def _file_suite_key(suite: str) -> str | None:
    """Map a run's suite label to a real source file, or None if not file-scoped.

    Project/tag/selection runs store display labels like ``Project: Demo`` in
    ``suite`` — those must not appear as rows in the per-file Insights table.
    Test Explorer runs use ``Suite: login.robot``; strip that prefix so the
    path matches composition / absolute suite runs.
    """
    text = (suite or "").strip()
    if not text:
        return None
    lower = text.lower()
    if lower.startswith(("project: ", "tag: ", "selected (")):
        return None
    if lower.startswith("suite: "):
        text = text[7:].strip()
        if not text:
            return None
        lower = text.lower()
    # "login.robot :: Test Name" → attribute to the file basename/path.
    if " :: " in text:
        text = text.split(" :: ", 1)[0].strip()
        if not text:
            return None
    path = Path(text)
    if path.suffix.lower() not in _FILE_SUFFIXES:
        return None
    return _normalize_path(str(path))


def _is_multi_file_label(suite: str) -> bool:
    label = (suite or "").strip().lower()
    return label.startswith(("project: ", "tag: ", "selected ("))


def _file_status_to_outcome(status: str, *, run_outcome: str) -> str:
    """Map a leaf suite status onto Insights Pass/Fail/Interrupted buckets."""
    value = (status or "").upper()
    if value == "FAIL":
        return "FAIL"
    if value == "PASS":
        return "PASS"
    if run_outcome in {"CANCELLED", "ABORTED"}:
        return run_outcome
    # SKIP / unknown — still a completed file participation, not a failure.
    return "PASS"


def _credit_file_bucket(
    bucket: dict,
    *,
    run: ExecutionRun,
    outcome: str,
) -> None:
    # NO TESTS / ERROR are history noise for per-file health — skip them.
    if outcome not in {"PASS", "FAIL", "CANCELLED", "ABORTED"}:
        return
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
        bucket["last_run_id"] = run.id
    if outcome == "FAIL":
        failed_at: datetime | None = bucket.get("last_failed_at")
        if failed_at is None or run.started_at > failed_at:
            bucket["last_failed_at"] = run.started_at
            bucket["last_failed_run_id"] = run.id


def _normalize_path(path: str) -> str:
    return path.replace("\\", "/").strip()


def _canonicalize_run_file(
    path: str,
    composition_paths: list[str],
) -> str:
    """Collapse absolute / relative / basename variants of the same suite file."""
    key = _normalize_path(path)
    if not key:
        return key

    normalized = [_normalize_path(p) for p in composition_paths]
    for candidate in normalized:
        if candidate == key:
            return candidate

    suffix_hits = [
        candidate
        for candidate in normalized
        if candidate.endswith("/" + key)
    ]
    if len(suffix_hits) == 1:
        return suffix_hits[0]

    name = Path(key).name
    if key == name:
        name_hits = [
            candidate for candidate in normalized if Path(candidate).name == name
        ]
        if len(name_hits) == 1:
            return name_hits[0]

    return key


def _merge_duplicate_file_buckets(
    by_file: dict[str, dict],
) -> dict[str, dict]:
    """Merge remaining path variants (basename vs longer path) after aggregation."""
    if len(by_file) < 2:
        return by_file

    keys = sorted(by_file.keys(), key=len, reverse=True)
    merged: dict[str, dict] = {}
    absorbed: set[str] = set()

    for key in keys:
        if key in absorbed:
            continue
        bucket = dict(by_file[key])
        for other in keys:
            if other == key or other in absorbed:
                continue
            # Absorb shorter keys that are a suffix / basename of this key.
            if key.endswith("/" + other) or (
                "/" not in other and Path(key).name == other
            ):
                _absorb_file_bucket(bucket, by_file[other])
                absorbed.add(other)
        merged[key] = bucket
        absorbed.add(key)

    return merged


def _absorb_file_bucket(target: dict, source: dict) -> None:
    target["runs"] += int(source["runs"])
    target["passed"] += int(source["passed"])
    target["failed"] += int(source["failed"])
    target["cancelled"] += int(source["cancelled"])
    target["aborted"] += int(source["aborted"])
    source_at: datetime | None = source["last_started_at"]
    target_at: datetime | None = target["last_started_at"]
    if source_at is not None and (target_at is None or source_at > target_at):
        target["last_started_at"] = source_at
        target["last_outcome"] = source["last_outcome"]
        target["last_run_id"] = source["last_run_id"]
    source_failed_at = source.get("last_failed_at")
    target_failed_at = target.get("last_failed_at")
    if source_failed_at is not None and (
        target_failed_at is None or source_failed_at > target_failed_at
    ):
        target["last_failed_at"] = source_failed_at
        target["last_failed_run_id"] = source["last_failed_run_id"]


def _empty_file_bucket() -> dict:
    return {
        "runs": 0,
        "passed": 0,
        "failed": 0,
        "cancelled": 0,
        "aborted": 0,
        "last_outcome": None,
        "last_started_at": None,
        "last_run_id": None,
        "last_failed_run_id": None,
        "last_failed_at": None,
    }


@dataclass
class InsightsService:
    context: WorkspaceContext
    index_store: IndexStore
    execution_repository: SqliteExecutionRepository

    async def get_snapshot(self, *, recent_limit: int = 30) -> InsightsSnapshot:
        workspace = self.context.workspace
        if workspace is None:
            raise InsightsValidationError("Open a workspace before viewing insights")

        started = time.perf_counter()
        totals = await self.index_store.composition_by_kind(workspace.id)
        raw_files = await self.index_store.composition_by_file(workspace.id)
        composition_files = [
            FileComposition(file_path=item["file_path"], counts=dict(item["counts"]))
            for item in raw_files
        ]
        composition_totals = _composition_totals(totals, composition_files)

        runs = await self.execution_repository.list_by_workspace(
            workspace.id,
            limit=500,
        )
        # Aggregation may parse one large output.xml on a cold sidecar miss —
        # keep that off the event loop.
        run_totals, recent, file_stats = await asyncio.to_thread(
            _aggregate_runs,
            runs,
            recent_limit=recent_limit,
            composition_files=composition_files,
        )

        index_status = await self.index_store.status(workspace.id)
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        message = (
            f"Insights snapshot ready in {elapsed_ms}ms "
            f"(runs={len(runs)} files={len(composition_files)})"
        )
        if elapsed_ms >= 5_000:
            logger.warning(message)
        else:
            logger.info(message)
        return InsightsSnapshot(
            composition_totals=composition_totals,
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
    composition_files: list[FileComposition] | None = None,
) -> tuple[RunOutcomeTotals, list[InsightsRecentRun], list[FileRunStats]]:
    passed = failed = cancelled = aborted = 0
    skipped_tests = 0
    durations: list[int] = []
    recent: list[InsightsRecentRun] = []
    by_file: dict[str, dict] = defaultdict(_empty_file_bucket)

    composition_paths = [item.file_path for item in (composition_files or [])]
    robot_files = [
        item.file_path
        for item in (composition_files or [])
        if str(item.file_path).lower().endswith(".robot")
    ]

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
        # NO TESTS / ERROR: keep in recent history, but do not score pass rate.

        skipped_tests += int(run.skipped or 0)
        if run.duration_ms is not None and outcome in {
            "PASS",
            "FAIL",
            "CANCELLED",
            "ABORTED",
        }:
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
        if path is None and _is_multi_file_label(run.suite):
            # Project/Tag/Selected runs: credit each leaf .robot from the
            # canonical sidecar (built from output.xml when missing).
            file_outcomes = load_or_build_file_outcomes(run.output_dir)
            if file_outcomes:
                for source, status in file_outcomes.items():
                    file_path = _canonicalize_run_file(source, composition_paths)
                    file_outcome = _file_status_to_outcome(
                        status,
                        run_outcome=outcome,
                    )
                    _credit_file_bucket(
                        by_file[file_path],
                        run=run,
                        outcome=file_outcome,
                    )
                continue
            if len(robot_files) == 1:
                path = robot_files[0]
            else:
                continue
        if not path:
            continue
        path = _canonicalize_run_file(path, composition_paths)
        _credit_file_bucket(by_file[path], run=run, outcome=outcome)

    by_file = _merge_duplicate_file_buckets(dict(by_file))

    # If composition was empty but every file-scoped run points at one suite,
    # fold Project:/Tag:/Selected runs into that sole file.
    if len(by_file) == 1 and len(robot_files) != 1:
        only_path = next(iter(by_file))
        only_bucket = by_file[only_path]
        for run in runs:
            if _file_suite_key(run.suite) is not None:
                continue
            if not _is_multi_file_label(run.suite):
                continue
            # Prefer xml fan-out when available so we do not double-count.
            if load_or_build_file_outcomes(run.output_dir):
                continue
            outcome = _run_outcome(run)
            _credit_file_bucket(only_bucket, run=run, outcome=outcome)

    # Pass rate matches Reports: only PASS vs FAIL. Empty (NO TESTS), ERROR,
    # cancelled, and aborted runs are excluded from the rate.
    scored = passed + failed
    counted = scored + cancelled + aborted
    pass_rate = (passed / scored * 100.0) if scored else None
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
            last_run_id=data.get("last_run_id"),
            last_failed_run_id=data.get("last_failed_run_id"),
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


def _composition_totals(
    raw_kind_counts: dict[str, int],
    composition_files: list[FileComposition],
) -> dict[str, int]:
    """Prefer real file/suite inventory over meta symbol rows.

    Indexing writes one ``file`` and one ``test_suite`` symbol per ``.robot``
    file. Those inflate "symbol" charts and can diverge from what users mean by
    Files / Suites. Count distinct indexed source paths instead.
    """
    totals = dict(raw_kind_counts)
    source_files = [
        item
        for item in composition_files
        if Path(item.file_path).suffix.lower()
        in {".robot", ".resource", ".py", ".yaml", ".yml"}
    ]
    robot_suites = [
        item
        for item in source_files
        if Path(item.file_path).suffix.lower() == ".robot"
    ]
    totals["file"] = len(source_files)
    totals["test_suite"] = len(robot_suites)
    # Test cases / keywords / variables stay as indexed definition counts.
    return totals
