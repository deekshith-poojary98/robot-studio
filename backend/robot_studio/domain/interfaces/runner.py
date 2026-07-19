from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from pathlib import Path
from uuid import UUID


class Runner(ABC):
    @abstractmethod
    async def start(self, request: dict) -> dict: ...

    @abstractmethod
    async def stop(self, run_id: UUID) -> None: ...

    @abstractmethod
    async def stream_output(self, run_id: UUID) -> AsyncIterator[str]: ...


class ResultsStore(ABC):
    @abstractmethod
    async def ingest(self, run_id: UUID, output_dir: Path) -> dict: ...

    @abstractmethod
    async def get(self, run_id: UUID) -> dict | None: ...

    @abstractmethod
    async def list_history(self, project_id: UUID) -> list[dict]: ...

    @abstractmethod
    async def discover_run(self, run_id: UUID, output_dir: Path) -> dict: ...

    @abstractmethod
    async def load_run(self, run_id: UUID) -> dict | None: ...

    @abstractmethod
    async def delete_run(self, run_id: UUID, output_dir: Path | None) -> None: ...

    @abstractmethod
    def dashboard_summary(self, runs: list) -> dict: ...


class ReportProvider(ABC):
    @abstractmethod
    async def list_artifacts(self, run_id: UUID) -> list[str]: ...

    @abstractmethod
    async def read_artifact(self, run_id: UUID, artifact: str) -> bytes: ...

    @abstractmethod
    def supports(self, run_id: UUID) -> bool: ...
