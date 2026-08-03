from abc import ABC, abstractmethod
from uuid import UUID

from robot_studio.domain.models import Environment


class EnvironmentRepository(ABC):
    @abstractmethod
    async def create(self, environment: Environment) -> Environment: ...

    @abstractmethod
    async def update(self, environment: Environment) -> Environment: ...

    @abstractmethod
    async def list_by_workspace(self, workspace_id: UUID) -> list[Environment]: ...

    @abstractmethod
    async def get(self, environment_id: UUID) -> Environment | None: ...

    @abstractmethod
    async def get_by_path(self, path: str) -> Environment | None: ...

    @abstractmethod
    async def set_active(self, workspace_id: UUID, environment_id: UUID) -> None: ...

    @abstractmethod
    async def clear_active(self, workspace_id: UUID) -> None: ...

    @abstractmethod
    async def delete(self, environment_id: UUID) -> None: ...

    @abstractmethod
    async def delete_by_workspace(self, workspace_id: UUID) -> int: ...
