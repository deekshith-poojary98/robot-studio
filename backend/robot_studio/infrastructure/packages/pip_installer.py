"""Pip-based Installer — first Installer capability implementation."""

from __future__ import annotations

import asyncio
import json
import re
import subprocess
import sys
from pathlib import Path

from robot_studio.domain.interfaces.installer import Installer
from robot_studio.domain.models import InstalledPackage
from robot_studio.infrastructure.environment.python_provider import (
    stable_subprocess_cwd,
)

_METADATA_SCRIPT = r"""
import json
import importlib.metadata as md

packages = []
for dist in md.distributions():
    name = dist.metadata["Name"] if dist.metadata and "Name" in dist.metadata else dist.name
    version = dist.version
    summary = dist.metadata.get("Summary") if dist.metadata else None
    author = dist.metadata.get("Author") if dist.metadata else None
    if not author and dist.metadata:
        author = dist.metadata.get("Author-email")
    homepage = None
    if dist.metadata:
        homepage = dist.metadata.get("Home-page")
        if not homepage:
            for value in dist.metadata.get_all("Project-URL") or []:
                label, _, url = value.partition(",")
                if label.strip().lower() in {"homepage", "home", "home page"}:
                    homepage = url.strip()
                    break
    license_name = dist.metadata.get("License") if dist.metadata else None
    location = str(dist.locate_file(""))
    requires = list(dist.requires or [])
    packages.append(
        {
            "name": name,
            "version": version,
            "summary": summary or None,
            "author": author or None,
            "homepage": homepage or None,
            "license": license_name or None,
            "location": location,
            "requires": requires,
        }
    )
print(json.dumps(packages))
"""


class PackageInstallError(Exception):
    """Raised when a pip operation fails."""

    def __init__(self, message: str, logs: list[str] | None = None) -> None:
        super().__init__(message)
        self.logs = logs or []


class PipInstaller(Installer):
    """Executes pip against a virtual environment's Python — never system Python."""

    async def list_installed(self, environment_path: Path) -> list[InstalledPackage]:
        python = self._python_for(environment_path)
        raw = await asyncio.to_thread(self._run_capture, python, ["-c", _METADATA_SCRIPT])
        try:
            items = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise PackageInstallError(
                f"Failed to parse installed package metadata: {exc}",
            ) from exc

        packages = [
            InstalledPackage(
                name=str(item["name"]),
                version=str(item["version"]),
                summary=item.get("summary"),
                author=item.get("author"),
                homepage=item.get("homepage"),
                license=item.get("license"),
                location=item.get("location"),
                requires=list(item.get("requires") or []),
            )
            for item in items
        ]
        outdated = await self._outdated_map(python)
        enriched: list[InstalledPackage] = []
        for package in packages:
            latest = outdated.get(package.name.lower())
            enriched.append(
                package.model_copy(
                    update={
                        "latest_version": latest or package.version,
                        "update_available": bool(
                            latest and latest != package.version,
                        ),
                    },
                ),
            )
        return enriched

    async def show(
        self,
        environment_path: Path,
        package: str,
    ) -> InstalledPackage | None:
        installed = await self.list_installed(environment_path)
        target = package.lower()
        for item in installed:
            if item.name.lower() == target:
                return item
        return None

    async def install(self, environment_path: Path, package: str) -> list[str]:
        python = self._python_for(environment_path)
        return await asyncio.to_thread(
            self._pip,
            python,
            ["install", package],
            error_prefix=f"Failed to install '{package}'",
        )

    async def install_requirements(
        self,
        environment_path: Path,
        requirements_file: Path,
    ) -> list[str]:
        python = self._python_for(environment_path)
        return await asyncio.to_thread(
            self._pip,
            python,
            ["install", "-r", str(requirements_file)],
            error_prefix=f"Failed to install requirements from '{requirements_file.name}'",
        )

    async def uninstall(self, environment_path: Path, package: str) -> list[str]:
        python = self._python_for(environment_path)
        return await asyncio.to_thread(
            self._pip,
            python,
            ["uninstall", "-y", package],
            error_prefix=f"Failed to uninstall '{package}'",
        )

    async def upgrade(self, environment_path: Path, package: str) -> list[str]:
        python = self._python_for(environment_path)
        return await asyncio.to_thread(
            self._pip,
            python,
            ["install", "--upgrade", package],
            error_prefix=f"Failed to update '{package}'",
        )

    async def _outdated_map(self, python: Path) -> dict[str, str]:
        # `pip list --outdated` can take tens of seconds on cold/network runs.
        # Never block package listing on it — update badges are best-effort.
        try:
            raw = await asyncio.wait_for(
                asyncio.to_thread(
                    self._run_capture,
                    python,
                    ["-m", "pip", "list", "--outdated", "--format=json"],
                ),
                timeout=8.0,
            )
            items = json.loads(raw or "[]")
        except (PackageInstallError, json.JSONDecodeError, TimeoutError, asyncio.TimeoutError):
            return {}
        result: dict[str, str] = {}
        for item in items:
            name = str(item.get("name", "")).lower()
            latest = item.get("latest_version")
            if name and latest:
                result[name] = str(latest)
        return result

    def _python_for(self, environment_path: Path) -> Path:
        root = Path(environment_path)
        if sys.platform == "win32":
            candidate = root / "Scripts" / "python.exe"
        else:
            candidate = root / "bin" / "python"
        if not candidate.is_file():
            raise PackageInstallError(
                f"Active environment Python not found at '{candidate}'",
            )
        return candidate.resolve()

    def _pip(self, python: Path, args: list[str], *, error_prefix: str) -> list[str]:
        command = [str(python), "-m", "pip", *args]
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            cwd=stable_subprocess_cwd(python.resolve().parent.parent),
        )
        logs = self._merge_logs(result.stdout, result.stderr)
        if result.returncode != 0:
            detail = "\n".join(logs[-20:]) if logs else "pip command failed"
            raise PackageInstallError(f"{error_prefix}: {detail}", logs=logs)
        return logs

    def _run_capture(self, python: Path, args: list[str]) -> str:
        result = subprocess.run(
            [str(python), *args],
            capture_output=True,
            text=True,
            check=False,
            cwd=stable_subprocess_cwd(python.resolve().parent.parent),
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "command failed").strip()
            raise PackageInstallError(detail)
        return result.stdout or ""

    @staticmethod
    def _merge_logs(stdout: str | None, stderr: str | None) -> list[str]:
        lines: list[str] = []
        for block in (stdout, stderr):
            if not block:
                continue
            for line in block.splitlines():
                cleaned = line.rstrip()
                if cleaned:
                    lines.append(cleaned)
        # Collapse noisy spinner updates from pip progress bars.
        cleaned_lines = [re.sub(r"\s+", " ", line).strip() for line in lines]
        return [line for line in cleaned_lines if line]
