"""Filesystem + metadata ResultsStore for Robot execution artifacts."""

from __future__ import annotations

import shutil
from pathlib import Path
from uuid import UUID

from robot_studio.domain.interfaces.runner import ResultsStore
from robot_studio.domain.models import ExecutionRun, ExecutionStatus
from robot_studio.infrastructure.execution.output_stats import parse_output_stats


class FilesystemResultsStore(ResultsStore):
    """Indexes Robot artifact paths and lightweight statistics."""

    def __init__(self) -> None:
        self._runs: dict[UUID, dict] = {}

    async def ingest(self, run_id: UUID, output_dir: Path) -> dict:
        return await self.discover_run(run_id, output_dir)

    async def discover_run(self, run_id: UUID, output_dir: Path) -> dict:
        root = Path(output_dir)
        output_xml = root / "output.xml" if (root / "output.xml").is_file() else None
        log_html = root / "log.html" if (root / "log.html").is_file() else None
        report_html = root / "report.html" if (root / "report.html").is_file() else None
        stats = parse_output_stats(output_xml)
        payload = {
            "run_id": str(run_id),
            "output_dir": str(root),
            "output_xml": str(output_xml) if output_xml else None,
            "log_html": str(log_html) if log_html else None,
            "report_html": str(report_html) if report_html else None,
            "robot_version": stats.get("robot_version"),
            "total_tests": stats.get("total_tests"),
            "passed": stats.get("passed"),
            "failed": stats.get("failed"),
            "skipped": stats.get("skipped"),
        }
        self._runs[run_id] = payload
        return payload

    async def get(self, run_id: UUID) -> dict | None:
        return self._runs.get(run_id)

    async def load_run(self, run_id: UUID) -> dict | None:
        return await self.get(run_id)

    async def list_history(self, project_id: UUID) -> list[dict]:
        # History persistence is handled by ExecutionRepository; this store is
        # artifact metadata only.
        _ = project_id
        return list(self._runs.values())

    async def delete_run(self, run_id: UUID, output_dir: Path | None) -> None:
        self._runs.pop(run_id, None)
        if output_dir is None:
            return
        root = Path(output_dir)
        if root.is_dir() and root.name.startswith("Run-"):
            shutil.rmtree(root, ignore_errors=True)

    def dashboard_summary(self, runs: list) -> dict:
        typed = [run for run in runs if isinstance(run, ExecutionRun)]
        finished = [
            run
            for run in typed
            if run.status
            in {
                ExecutionStatus.FINISHED,
                ExecutionStatus.FAILED,
                ExecutionStatus.CANCELLED,
            }
        ]
        total_runs = len(finished)
        pass_runs = [run for run in finished if run.result_badge() == "PASS"]
        scored = [
            run for run in finished if run.result_badge() in {"PASS", "FAIL"}
        ]
        durations = [run.duration_ms for run in finished if run.duration_ms is not None]
        failures = [run for run in finished if run.result_badge() == "FAIL"]
        return {
            "total_runs": total_runs,
            "pass_rate": (len(pass_runs) / len(scored) * 100.0) if scored else None,
            "average_duration_ms": (sum(durations) / len(durations)) if durations else None,
            "last_run": finished[0] if finished else None,
            "recent_runs": finished[:5],
            "recent_failures": failures[:5],
        }

    def apply_to_run(self, run: ExecutionRun, artifacts: dict) -> ExecutionRun:
        return run.model_copy(
            update={
                "output_dir": Path(artifacts["output_dir"]) if artifacts.get("output_dir") else None,
                "output_xml": (
                    Path(artifacts["output_xml"]) if artifacts.get("output_xml") else None
                ),
                "log_html": Path(artifacts["log_html"]) if artifacts.get("log_html") else None,
                "report_html": (
                    Path(artifacts["report_html"]) if artifacts.get("report_html") else None
                ),
                "robot_version": artifacts.get("robot_version"),
                "total_tests": artifacts.get("total_tests"),
                "passed": artifacts.get("passed"),
                "failed": artifacts.get("failed"),
                "skipped": artifacts.get("skipped"),
            },
        )
