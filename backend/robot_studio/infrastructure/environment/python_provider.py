"""Python virtual environment operations via stdlib venv + subprocess."""

from __future__ import annotations

import platform
import re
import subprocess
import sys
import venv
from dataclasses import dataclass
from pathlib import Path

from robot_studio.infrastructure.environment.filesystem import (
    EnvironmentValidationError,
)

_VERSION_RE = re.compile(r"(\d+\.\d+(?:\.\d+)?)")


@dataclass(frozen=True)
class ResolvedExecutables:
    python: Path
    pip: Path
    robot: Path | None


@dataclass(frozen=True)
class RuntimeInfo:
    python_version: str
    platform: str
    architecture: str
    robot_version: str | None
    package_count: int


class PythonEnvironmentProvider:
    def create_venv(self, python_executable: Path, target_dir: Path) -> None:
        python = self._resolve_base_python(python_executable)
        if target_dir.exists() and any(target_dir.iterdir()):
            raise EnvironmentValidationError(
                f"Environment directory is not empty: '{target_dir}'",
            )

        # Prefer the selected interpreter so the venv matches the chosen version.
        if Path(python).resolve() == Path(sys.executable).resolve():
            builder = venv.EnvBuilder(with_pip=True, clear=False, upgrade_deps=False)
            builder.create(target_dir)
            return

        result = subprocess.run(
            [str(python), "-m", "venv", str(target_dir)],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "venv creation failed").strip()
            raise EnvironmentValidationError(
                f"Failed to create virtual environment: {detail}",
            )

    def resolve_executables(self, environment_root: Path) -> ResolvedExecutables:
        if sys.platform == "win32":
            scripts = environment_root / "Scripts"
            python = scripts / "python.exe"
            pip = scripts / "pip.exe"
            robot = scripts / "robot.exe"
        else:
            scripts = environment_root / "bin"
            python = scripts / "python"
            pip = scripts / "pip"
            robot = scripts / "robot"

        if not python.is_file():
            raise EnvironmentValidationError(
                f"Python executable not found in '{environment_root}'",
            )
        if not pip.is_file():
            # Fallback: python -m pip still works; store python -m path hint via python
            pip = python

        return ResolvedExecutables(
            python=python.resolve(),
            pip=pip.resolve() if pip.is_file() else python.resolve(),
            robot=robot.resolve() if robot.is_file() else None,
        )

    def get_python_version(self, python_executable: Path) -> str:
        output = self._run(
            [str(python_executable), "-c", "import sys; print("
             "f'{sys.version_info.major}.{sys.version_info.minor}')"],
            error_prefix="Failed to read Python version",
        )
        match = _VERSION_RE.search(output)
        if not match:
            raise EnvironmentValidationError(
                f"Could not parse Python version from: {output!r}",
            )
        return match.group(1)

    def get_robot_version(self, python_executable: Path) -> str | None:
        result = subprocess.run(
            [
                str(python_executable),
                "-c",
                "import importlib.metadata as m; print(m.version('robotframework'))",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return None
        text = (result.stdout or "").strip()
        return text or None

    def count_packages(self, python_executable: Path) -> int:
        result = subprocess.run(
            [str(python_executable), "-m", "pip", "list", "--format=freeze"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return 0
        lines = [
            line.strip()
            for line in (result.stdout or "").splitlines()
            if line.strip() and not line.startswith("#")
        ]
        return len(lines)

    def get_platform_info(self, python_executable: Path) -> tuple[str, str]:
        result = subprocess.run(
            [
                str(python_executable),
                "-c",
                "import platform, sys; "
                "print(sys.platform); print(platform.machine())",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return platform.system().lower(), platform.machine()
        lines = [line.strip() for line in (result.stdout or "").splitlines() if line.strip()]
        if len(lines) >= 2:
            return lines[0], lines[1]
        return platform.system().lower(), platform.machine()

    def inspect(self, python_executable: Path) -> RuntimeInfo:
        python_version = self.get_python_version(python_executable)
        plat, arch = self.get_platform_info(python_executable)
        return RuntimeInfo(
            python_version=python_version,
            platform=plat,
            architecture=arch,
            robot_version=self.get_robot_version(python_executable),
            package_count=self.count_packages(python_executable),
        )

    def install_robot_framework(self, python_executable: Path) -> None:
        result = subprocess.run(
            [str(python_executable), "-m", "pip", "install", "robotframework"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "pip install failed").strip()
            raise EnvironmentValidationError(
                f"Failed to install Robot Framework: {detail}",
            )

    def freeze_requirements(self, python_executable: Path, target_file: Path) -> None:
        result = subprocess.run(
            [str(python_executable), "-m", "pip", "freeze"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "pip freeze failed").strip()
            raise EnvironmentValidationError(
                f"Failed to freeze packages: {detail}",
            )
        target_file.write_text(result.stdout or "", encoding="utf-8")

    def install_requirements(
        self,
        python_executable: Path,
        requirements_file: Path,
    ) -> None:
        if not requirements_file.is_file():
            return
        content = requirements_file.read_text(encoding="utf-8").strip()
        if not content:
            return
        result = subprocess.run(
            [
                str(python_executable),
                "-m",
                "pip",
                "install",
                "-r",
                str(requirements_file),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "pip install -r failed").strip()
            raise EnvironmentValidationError(
                f"Failed to install cloned packages: {detail}",
            )

    def _resolve_base_python(self, python_executable: Path) -> Path:
        path = Path(python_executable).expanduser()
        if not path.exists():
            raise EnvironmentValidationError(
                f"Python interpreter not found: '{path}'",
            )
        return path.resolve()

    def _run(self, command: list[str], *, error_prefix: str) -> str:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "command failed").strip()
            raise EnvironmentValidationError(f"{error_prefix}: {detail}")
        return (result.stdout or "").strip()
