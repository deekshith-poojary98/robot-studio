"""Package management use cases for the active environment."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import (
    EventBus,
    PackageInstalled,
    PackageRemoved,
    PackageUpdated,
    RobotFrameworkInstalled,
)
from robot_studio.domain.interfaces.installer import Installer, PackageRegistry
from robot_studio.domain.models import Environment, InstalledPackage, PackageSearchResult
from robot_studio.infrastructure.packages.package_match import rank_packages
from robot_studio.infrastructure.packages.pip_installer import PackageInstallError

PROTECTED_PACKAGES = frozenset({"pip", "setuptools", "wheel"})
SortKey = str  # "name" | "version" | "update"


class PackageValidationError(Exception):
    """Raised when package operations fail validation."""


@dataclass(frozen=True)
class PackageListResult:
    packages: list[InstalledPackage]
    robot_framework_installed: bool
    robot_framework_version: str | None
    environment: Environment


@dataclass(frozen=True)
class PackageOperationResult:
    package: InstalledPackage | None
    logs: list[str]
    robot_framework_installed: bool
    robot_framework_version: str | None


class PackageService:
    def __init__(
        self,
        context: WorkspaceContext,
        event_bus: EventBus,
        installer: Installer,
        registry: PackageRegistry,
    ) -> None:
        self._context = context
        self._event_bus = event_bus
        self._installer = installer
        self._registry = registry

    def _require_environment(self) -> Environment:
        workspace = self._context.workspace
        if workspace is None:
            raise PackageValidationError(
                "Open a workspace before managing packages",
            )
        environment = self._context.environment
        if environment is None:
            raise PackageValidationError(
                "Activate a Python environment before managing packages",
            )
        if not environment.path.is_dir():
            raise PackageValidationError(
                f"Active environment directory is missing: '{environment.path}'",
            )
        return environment

    async def list_packages(
        self,
        *,
        query: str | None = None,
        sort: SortKey = "name",
    ) -> PackageListResult:
        environment = self._require_environment()
        packages = await self._installer.list_installed(environment.path)

        if query and query.strip():
            # Relevance first (exact > prefix > substring > fuzzy). The sort
            # dropdown only applies when there is no active query.
            packages = rank_packages(packages, query)
        else:
            packages = self._sort(packages, sort)
        robot = self._find_robot(packages)
        return PackageListResult(
            packages=packages,
            robot_framework_installed=robot is not None,
            robot_framework_version=robot.version if robot else None,
            environment=environment,
        )

    async def search_packages(self, query: str) -> list[PackageSearchResult]:
        cleaned = query.strip()
        if not cleaned:
            raise PackageValidationError("Search query is required")
        # Ensure an active environment exists so installs are meaningful.
        self._require_environment()
        results = await self._registry.search(cleaned)
        mapped = [
            PackageSearchResult(
                name=str(item.get("name", "")),
                latest_version=str(item.get("latest_version") or ""),
                summary=item.get("summary"),
            )
            for item in results
            if item.get("name")
        ]
        # Re-rank remote hits with the same deterministic contract so an exact
        # / prefix hit is never buried under a weaker match, and keep the
        # dialog list to a readable top 20.
        return rank_packages(mapped, cleaned)[:20]

    async def list_package_versions(self, name: str) -> list[str]:
        cleaned = name.strip()
        if not cleaned:
            raise PackageValidationError("Package name is required")
        self._require_environment()
        versions = await self._registry.list_versions(cleaned)
        if not versions:
            raise PackageValidationError(
                f"No versions found for package '{cleaned}'",
            )
        return versions

    async def get_package(self, name: str) -> InstalledPackage:
        environment = self._require_environment()
        package = await self._installer.show(environment.path, name)
        if package is None:
            raise PackageValidationError(
                f"Package '{name}' is not installed in the active environment",
            )
        return await self._merge_pypi_details(package)

    async def install_package(
        self,
        name: str,
        *,
        version: str | None = None,
    ) -> PackageOperationResult:
        environment = self._require_environment()
        cleaned = name.strip()
        if not cleaned:
            raise PackageValidationError("Package name is required")

        requirement = cleaned
        if version is not None and version.strip():
            selected = version.strip()
            if any(ch in selected for ch in " \t\n\"';|&"):
                raise PackageValidationError("Invalid package version")
            requirement = f"{cleaned}=={selected}"

        try:
            logs = await self._installer.install(environment.path, requirement)
        except PackageInstallError as exc:
            raise PackageValidationError(str(exc)) from exc

        package = await self._installer.show(environment.path, cleaned)
        if package is not None:
            package = await self._merge_pypi_details(package)

        workspace = self._context.workspace
        assert workspace is not None
        await self._event_bus.publish(
            PackageInstalled(
                workspace_id=workspace.id,
                environment_id=environment.id,
                package_name=package.name if package else cleaned,
            ),
        )

        robot = await self._robot_status(environment)
        if cleaned.lower().replace("-", "") == "robotframework" or (
            package and package.name.lower() == "robotframework"
        ):
            await self._event_bus.publish(
                RobotFrameworkInstalled(
                    workspace_id=workspace.id,
                    environment_id=environment.id,
                    version=robot[1],
                ),
            )

        return PackageOperationResult(
            package=package,
            logs=logs,
            robot_framework_installed=robot[0],
            robot_framework_version=robot[1],
        )

    async def install_requirements(self, file_path: str) -> PackageOperationResult:
        environment = self._require_environment()
        raw = file_path.strip()
        if not raw:
            raise PackageValidationError("Requirements file path is required")
        if "\x00" in raw or "\n" in raw or "\r" in raw:
            raise PackageValidationError("Invalid requirements file path")

        try:
            requirements = Path(raw).expanduser().resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise PackageValidationError(
                f"Requirements file was not found: '{raw}'",
            ) from exc
        if not requirements.is_file():
            raise PackageValidationError(
                f"Requirements path is not a file: '{requirements}'",
            )
        if requirements.suffix.lower() not in {".txt", ".in"}:
            raise PackageValidationError(
                "Choose a requirements .txt or .in file",
            )
        try:
            if requirements.stat().st_size > 2_000_000:
                raise PackageValidationError(
                    "Requirements file is larger than 2 MB",
                )
        except OSError as exc:
            raise PackageValidationError(
                f"Could not read requirements file: '{requirements}'",
            ) from exc

        before = await self._installer.list_installed(environment.path)
        before_versions = {item.name.lower(): item.version for item in before}
        try:
            logs = await self._installer.install_requirements(
                environment.path,
                requirements,
            )
        except PackageInstallError as exc:
            raise PackageValidationError(str(exc)) from exc

        after = await self._installer.list_installed(environment.path)
        workspace = self._context.workspace
        assert workspace is not None
        for package in after:
            previous = before_versions.get(package.name.lower())
            if previous == package.version:
                continue
            event = (
                PackageInstalled(
                    workspace_id=workspace.id,
                    environment_id=environment.id,
                    package_name=package.name,
                )
                if previous is None
                else PackageUpdated(
                    workspace_id=workspace.id,
                    environment_id=environment.id,
                    package_name=package.name,
                )
            )
            await self._event_bus.publish(event)

        robot = self._find_robot(after)
        robot_was_installed = self._find_robot(before) is not None
        if robot is not None and not robot_was_installed:
            await self._event_bus.publish(
                RobotFrameworkInstalled(
                    workspace_id=workspace.id,
                    environment_id=environment.id,
                    version=robot.version,
                ),
            )

        return PackageOperationResult(
            package=None,
            logs=logs,
            robot_framework_installed=robot is not None,
            robot_framework_version=robot.version if robot else None,
        )

    async def update_package(self, name: str) -> PackageOperationResult:
        environment = self._require_environment()
        cleaned = name.strip()
        if not cleaned:
            raise PackageValidationError("Package name is required")

        existing = await self._installer.show(environment.path, cleaned)
        if existing is None:
            raise PackageValidationError(
                f"Package '{cleaned}' is not installed in the active environment",
            )

        try:
            logs = await self._installer.upgrade(environment.path, cleaned)
        except PackageInstallError as exc:
            raise PackageValidationError(str(exc)) from exc

        package = await self._installer.show(environment.path, cleaned)
        if package is not None:
            package = await self._merge_pypi_details(package)

        workspace = self._context.workspace
        assert workspace is not None
        await self._event_bus.publish(
            PackageUpdated(
                workspace_id=workspace.id,
                environment_id=environment.id,
                package_name=package.name if package else cleaned,
            ),
        )

        robot = await self._robot_status(environment)
        return PackageOperationResult(
            package=package,
            logs=logs,
            robot_framework_installed=robot[0],
            robot_framework_version=robot[1],
        )

    async def uninstall_package(self, name: str) -> PackageOperationResult:
        environment = self._require_environment()
        cleaned = name.strip()
        if not cleaned:
            raise PackageValidationError("Package name is required")
        if cleaned.lower() in PROTECTED_PACKAGES:
            raise PackageValidationError(
                f"Cannot uninstall protected package '{cleaned}'",
            )

        existing = await self._installer.show(environment.path, cleaned)
        if existing is None:
            raise PackageValidationError(
                f"Package '{cleaned}' is not installed in the active environment",
            )

        try:
            logs = await self._installer.uninstall(environment.path, cleaned)
        except PackageInstallError as exc:
            raise PackageValidationError(str(exc)) from exc

        workspace = self._context.workspace
        assert workspace is not None
        await self._event_bus.publish(
            PackageRemoved(
                workspace_id=workspace.id,
                environment_id=environment.id,
                package_name=existing.name,
            ),
        )

        robot = await self._robot_status(environment)
        return PackageOperationResult(
            package=None,
            logs=logs,
            robot_framework_installed=robot[0],
            robot_framework_version=robot[1],
        )

    async def install_robot_framework(self) -> PackageOperationResult:
        return await self.install_package("robotframework")

    async def _merge_pypi_details(self, package: InstalledPackage) -> InstalledPackage:
        meta = await self._registry.get_metadata(package.name)
        if meta is None:
            return package
        latest = meta.get("latest_version") or package.latest_version or package.version
        return package.model_copy(
            update={
                "latest_version": latest,
                "update_available": bool(latest and latest != package.version),
                "summary": package.summary or meta.get("summary"),
                "author": package.author or meta.get("author"),
                "homepage": package.homepage or meta.get("homepage"),
                "license": package.license or meta.get("license"),
                "requires": package.requires or list(meta.get("requires") or []),
            },
        )

    async def _robot_status(
        self,
        environment: Environment,
    ) -> tuple[bool, str | None]:
        packages = await self._installer.list_installed(environment.path)
        robot = self._find_robot(packages)
        return (robot is not None, robot.version if robot else None)

    @staticmethod
    def _find_robot(packages: list[InstalledPackage]) -> InstalledPackage | None:
        for package in packages:
            if package.name.lower() == "robotframework":
                return package
        return None

    @staticmethod
    def _sort(packages: list[InstalledPackage], sort: SortKey) -> list[InstalledPackage]:
        key = (sort or "name").lower()
        if key == "version":
            return sorted(packages, key=lambda item: item.version.lower())
        if key in {"update", "update_available"}:
            return sorted(
                packages,
                key=lambda item: (0 if item.update_available else 1, item.name.lower()),
            )
        return sorted(packages, key=lambda item: item.name.lower())

