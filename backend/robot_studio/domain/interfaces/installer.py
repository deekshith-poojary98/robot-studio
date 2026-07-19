from abc import ABC, abstractmethod
from pathlib import Path

from robot_studio.domain.models import InstalledPackage


class PackageRegistry(ABC):
    @abstractmethod
    async def search(self, query: str) -> list[dict]: ...

    @abstractmethod
    async def get_latest_version(self, name: str) -> str | None: ...

    @abstractmethod
    async def get_metadata(self, name: str) -> dict | None: ...


class Installer(ABC):
    @abstractmethod
    async def list_installed(self, environment_path: Path) -> list[InstalledPackage]: ...

    @abstractmethod
    async def show(
        self,
        environment_path: Path,
        package: str,
    ) -> InstalledPackage | None: ...

    @abstractmethod
    async def install(self, environment_path: Path, package: str) -> list[str]: ...

    @abstractmethod
    async def uninstall(self, environment_path: Path, package: str) -> list[str]: ...

    @abstractmethod
    async def upgrade(self, environment_path: Path, package: str) -> list[str]: ...
