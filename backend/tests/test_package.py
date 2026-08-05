"""Unit tests for package management."""

from __future__ import annotations

from pathlib import Path
import sys
from unittest.mock import AsyncMock

import pytest

from robot_studio.application.services.environment_service import EnvironmentService
from robot_studio.application.services.package_service import (
    PackageService,
    PackageValidationError,
)
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.application.services.workspace_service import WorkspaceService
from robot_studio.core.events import (
    InMemoryEventBus,
    PackageInstalled,
    PackageRemoved,
    PackageUpdated,
    RobotFrameworkInstalled,
)
from robot_studio.domain.models import InstalledPackage, PackageSearchResult
from robot_studio.infrastructure.environment.filesystem import (
    FilesystemEnvironmentProvider,
)
from robot_studio.infrastructure.environment.python_provider import (
    PythonEnvironmentProvider,
)
from robot_studio.infrastructure.packages.pip_installer import PipInstaller
from robot_studio.infrastructure.repositories.environment_repository import (
    SqliteEnvironmentRepository,
)
from robot_studio.infrastructure.repositories.workspace_repository import (
    SqliteWorkspaceRepository,
)


class FakeRegistry:
    async def search(self, query: str) -> list[dict]:
        return [
            {
                "name": "demo-pkg",
                "latest_version": "1.2.3",
                "summary": f"Result for {query}",
            },
        ]

    async def get_latest_version(self, name: str) -> str | None:
        meta = await self.get_metadata(name)
        return meta["latest_version"] if meta else None

    async def get_metadata(self, name: str) -> dict | None:
        return {
            "name": name,
            "latest_version": "9.9.9",
            "summary": "Fake summary",
            "author": "Tester",
            "homepage": "https://example.com",
            "license": "MIT",
            "requires": [],
        }

    async def list_versions(self, name: str) -> list[str]:
        return ["9.9.9", "9.0.0", "8.0.0"]


@pytest.fixture
async def services(tmp_path: Path):
    db = tmp_path / "test.db"
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)

    workspace_repo = SqliteWorkspaceRepository(db)
    await workspace_repo.initialize()
    workspace_service = WorkspaceService(workspace_repo, context)

    env_repo = SqliteEnvironmentRepository(db)
    await env_repo.initialize()
    environment_service = EnvironmentService(
        repository=env_repo,
        context=context,
        event_bus=bus,
        filesystem=FilesystemEnvironmentProvider(),
        python=PythonEnvironmentProvider(),
    )

    homes = tmp_path / "homes"
    homes.mkdir()
    await workspace_service.create_workspace("WS", homes)
    environment = await environment_service.create_environment(
        "pkg-env",
        sys.executable,
        install_robot_framework=False,
    )

    package_service = PackageService(
        context=context,
        event_bus=bus,
        installer=PipInstaller(),
        registry=FakeRegistry(),
    )
    return {
        "bus": bus,
        "context": context,
        "environment": environment,
        "package_service": package_service,
    }


@pytest.mark.asyncio
async def test_search_packages(services) -> None:
    results = await services["package_service"].search_packages("demo")
    assert isinstance(results[0], PackageSearchResult)
    assert results[0].name == "demo-pkg"
    assert results[0].latest_version == "1.2.3"


@pytest.mark.asyncio
async def test_install_and_list_and_uninstall(services) -> None:
    events: list[object] = []

    async def on_installed(event: PackageInstalled) -> None:
        events.append(event)

    async def on_removed(event: PackageRemoved) -> None:
        events.append(event)

    services["bus"].subscribe(PackageInstalled, on_installed)
    services["bus"].subscribe(PackageRemoved, on_removed)

    installed = await services["package_service"].install_package("six")
    assert installed.package is not None
    assert installed.package.name.lower() == "six"
    assert any(isinstance(e, PackageInstalled) for e in events)

    listed = await services["package_service"].list_packages()
    names = {item.name.lower() for item in listed.packages}
    assert "six" in names
    assert listed.environment.id == services["environment"].id

    detail = await services["package_service"].get_package("six")
    assert detail.latest_version == "9.9.9"
    assert detail.homepage  # from installed metadata or PyPI

    removed = await services["package_service"].uninstall_package("six")
    assert removed.package is None
    assert any(isinstance(e, PackageRemoved) for e in events)

    listed_after = await services["package_service"].list_packages()
    assert "six" not in {item.name.lower() for item in listed_after.packages}


@pytest.mark.asyncio
async def test_update_package(services) -> None:
    events: list[object] = []

    async def on_updated(event: PackageUpdated) -> None:
        events.append(event)

    services["bus"].subscribe(PackageUpdated, on_updated)

    await services["package_service"].install_package("six")
    updated = await services["package_service"].update_package("six")
    assert updated.package is not None
    assert any(isinstance(e, PackageUpdated) for e in events)


@pytest.mark.asyncio
async def test_install_requirements_uses_active_environment(
    services,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    requirements = tmp_path / "requirements.txt"
    requirements.write_text("robotframework==7.0\nsix==1.16.0\n", encoding="utf-8")
    installer = services["package_service"]._installer
    before = [InstalledPackage(name="pip", version="25.0")]
    after = [
        *before,
        InstalledPackage(name="robotframework", version="7.0"),
        InstalledPackage(name="six", version="1.16.0"),
    ]
    list_installed = AsyncMock(side_effect=[before, after])
    install_requirements = AsyncMock(return_value=["Successfully installed"])
    monkeypatch.setattr(installer, "list_installed", list_installed)
    monkeypatch.setattr(installer, "install_requirements", install_requirements)

    result = await services["package_service"].install_requirements(
        str(requirements),
    )

    install_requirements.assert_awaited_once_with(
        services["environment"].path,
        requirements.resolve(),
    )
    assert result.package is None
    assert result.logs == ["Successfully installed"]
    assert result.robot_framework_installed is True
    assert result.robot_framework_version == "7.0"


@pytest.mark.asyncio
async def test_install_requirements_rejects_wrong_file_type(
    services,
    tmp_path: Path,
) -> None:
    requirements = tmp_path / "requirements.yaml"
    requirements.write_text("packages: []\n", encoding="utf-8")

    with pytest.raises(PackageValidationError, match=r"\.txt or \.in"):
        await services["package_service"].install_requirements(str(requirements))


@pytest.mark.asyncio
async def test_cannot_uninstall_protected(services) -> None:
    with pytest.raises(PackageValidationError, match="protected"):
        await services["package_service"].uninstall_package("pip")


@pytest.mark.asyncio
async def test_requires_active_environment(tmp_path: Path) -> None:
    bus = InMemoryEventBus()
    context = WorkspaceContext(bus)
    service = PackageService(
        context=context,
        event_bus=bus,
        installer=PipInstaller(),
        registry=FakeRegistry(),
    )
    with pytest.raises(PackageValidationError, match="workspace"):
        await service.list_packages()


@pytest.mark.asyncio
async def test_robot_framework_detection(services) -> None:
    events: list[object] = []

    async def on_robot(event: RobotFrameworkInstalled) -> None:
        events.append(event)

    services["bus"].subscribe(RobotFrameworkInstalled, on_robot)

    before = await services["package_service"].list_packages()
    assert before.robot_framework_installed is False

    result = await services["package_service"].install_robot_framework()
    assert result.robot_framework_installed is True
    assert any(isinstance(e, RobotFrameworkInstalled) for e in events)

    after = await services["package_service"].list_packages()
    assert after.robot_framework_installed is True
    assert after.robot_framework_version


@pytest.mark.asyncio
async def test_installer_uses_environment_python(services) -> None:
    installer = PipInstaller()
    python = installer._python_for(services["environment"].path)
    assert str(services["environment"].path) in str(python)
    assert python.is_file()
