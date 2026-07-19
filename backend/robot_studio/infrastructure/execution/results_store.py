"""Filesystem + metadata ResultsStore for Robot execution artifacts."""

from __future__ import annotations

from pathlib import Path
from uuid import UUID

from robot_studio.domain.interfaces.runner import ResultsStore
from robot_studio.domain.models import ExecutionRun


class FilesystemResultsStore(ResultsStore):
    """Tracks artifact paths without parsing Robot output."""

    def __init__(self) -> None:
        self._runs: dict[UUID, dict] = {}

    async def ingest(self, run_id: UUID, output_dir: Path) -> dict:
        root = Path(output_dir)
        payload = {
            "run_id": str(run_id),
            "output_dir": str(root),
            "output_xml": str(root / "output.xml") if (root / "output.xml").is_file() else None,
            "log_html": str(root / "log.html") if (root / "log.html").is_file() else None,
            "report_html": (
                str(root / "report.html") if (root / "report.html").is_file() else None
            ),
        }
        self._runs[run_id] = payload
        return payload

    async def get(self, run_id: UUID) -> dict | None:
        return self._runs.get(run_id)

    async def list_history(self, project_id: UUID) -> list[dict]:
        # History persistence is handled by ExecutionRepository; this store is
        # in-memory artifact metadata only.
        _ = project_id
        return list(self._runs.values())

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
            },
        )
