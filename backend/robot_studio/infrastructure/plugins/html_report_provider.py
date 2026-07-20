"""Built-in HTML report provider."""

from __future__ import annotations

from pathlib import Path
from uuid import UUID

from robot_studio.domain.interfaces.runner import ReportProvider


class HtmlReportProvider(ReportProvider):
    """Reads Robot Framework HTML/XML artifacts from run output directories."""

    def __init__(self, artifacts: dict[UUID, dict[str, Path | None]] | None = None) -> None:
        self._artifacts = artifacts if artifacts is not None else {}

    def remember(self, run_id: UUID, artifacts: dict[str, Path | None]) -> None:
        self._artifacts[run_id] = artifacts

    async def list_artifacts(self, run_id: UUID) -> list[str]:
        data = self._artifacts.get(run_id, {})
        return [name for name, path in data.items() if path is not None and path.is_file()]

    async def read_artifact(self, run_id: UUID, artifact: str) -> bytes:
        data = self._artifacts.get(run_id, {})
        path = data.get(artifact)
        if path is None or not path.is_file():
            raise FileNotFoundError(f"Artifact '{artifact}' not found for run {run_id}")
        return path.read_bytes()

    def supports(self, run_id: UUID) -> bool:
        return bool(self._artifacts.get(run_id))
