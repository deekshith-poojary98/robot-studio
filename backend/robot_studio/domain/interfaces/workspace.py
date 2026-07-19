from abc import ABC, abstractmethod
from pathlib import Path
from uuid import UUID

from robot_studio.domain.models import Workspace


class WorkspaceRepository(ABC):
    @abstractmethod
    async def create(self, workspace: Workspace) -> Workspace: ...

    @abstractmethod
    async def list_all(self) -> list[Workspace]: ...

    @abstractmethod
    async def get(self, workspace_id: UUID) -> Workspace | None: ...

    @abstractmethod
    async def get_by_path(self, path: Path) -> Workspace | None: ...

    @abstractmethod
    async def record_recent(self, workspace: Workspace) -> None: ...

    @abstractmethod
    async def list_recent(self, limit: int = 10) -> list[Workspace]: ...
