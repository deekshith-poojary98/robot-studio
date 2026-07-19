from abc import ABC, abstractmethod
from uuid import UUID

from robot_studio.domain.models import Project


class ProjectRepository(ABC):
    @abstractmethod
    async def create(self, project: Project) -> Project: ...

    @abstractmethod
    async def list_by_workspace(self, workspace_id: UUID) -> list[Project]: ...

    @abstractmethod
    async def get(self, project_id: UUID) -> Project | None: ...

    @abstractmethod
    async def get_by_path(self, path: str) -> Project | None: ...

    @abstractmethod
    async def record_recent(self, project: Project) -> None: ...

    @abstractmethod
    async def list_recent(self, limit: int = 10) -> list[Project]: ...
