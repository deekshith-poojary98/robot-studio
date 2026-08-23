"""Invoke robot.api.parsing in the active workspace Python environment."""

from __future__ import annotations

import asyncio
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from robot_studio.infrastructure.environment.python_provider import (
    PythonEnvironmentProvider,
    _absolute_keep_wrapper,
    _host_python_subprocess_env,
)
from robot_studio.infrastructure.process_utils import windows_no_window_kwargs


class RobotParsingError(Exception):
    """Raised when Robot parsing cannot run in the active environment."""


def _robot_parsing_worker_source() -> Path:
    """Locate robot_parsing_worker.py (dev tree or PyInstaller datas)."""
    here = Path(__file__).resolve().with_name("robot_parsing_worker.py")
    if here.is_file():
        return here
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        bundled = (
            Path(meipass)
            / "robot_studio"
            / "infrastructure"
            / "language"
            / "robot_parsing_worker.py"
        )
        if bundled.is_file():
            return bundled
    raise RobotParsingError(
        "Robot parsing worker is missing from this install. "
        "Reinstall or re-download Robot Studio.",
    )


class RobotParsingBridge:
    """Runs robot_parsing_worker.py using the workspace venv Python."""

    def __init__(
        self,
        python_provider: PythonEnvironmentProvider | None = None,
    ) -> None:
        self._python = python_provider or PythonEnvironmentProvider()
        self._worker = _robot_parsing_worker_source()

    async def run(
        self,
        python_executable: Path,
        *,
        op: str,
        content: str = "",
        file_path: str = "",
        line: int = 1,
        column: int = 1,
        library: str = "",
        hover: bool = False,
    ) -> Any:
        if not python_executable.is_file():
            raise RobotParsingError(
                f"Python interpreter not found: '{python_executable}'",
            )
        payload = {
            "op": op,
            "content": content,
            "file_path": file_path,
            "line": line,
            "column": column,
            "library": library,
            "hover": hover,
        }
        return await asyncio.to_thread(
            self._run_sync,
            python_executable,
            payload,
        )

    def _run_sync(self, python_executable: Path, payload: dict[str, Any]) -> Any:
        command = [
            str(python_executable),
            str(self._worker),
        ]
        try:
            completed = subprocess.run(
                command,
                input=json.dumps(payload),
                capture_output=True,
                text=True,
                check=False,
                timeout=30,
                env=_host_python_subprocess_env(),
                **windows_no_window_kwargs(),
            )
        except subprocess.TimeoutExpired as exc:
            raise RobotParsingError("Robot parsing timed out") from exc
        except OSError as exc:
            raise RobotParsingError(f"Failed to start Robot parser: {exc}") from exc

        stdout = (completed.stdout or "").strip()
        stderr = (completed.stderr or "").strip()
        if not stdout:
            detail = stderr or f"Parser exited with code {completed.returncode}"
            raise RobotParsingError(detail)

        try:
            response = json.loads(stdout)
        except json.JSONDecodeError as exc:
            raise RobotParsingError(
                f"Invalid parser response: {stdout[:200]}",
            ) from exc

        if not response.get("ok"):
            raise RobotParsingError(str(response.get("error") or "Parser failed"))
        return response.get("result")

    def resolve_python(self, environment_path: Path | None) -> Path:
        if environment_path is None:
            raise RobotParsingError("Activate an environment with Robot Framework")
        if sys.platform == "win32":
            candidate = environment_path / "Scripts" / "python.exe"
        else:
            candidate = environment_path / "bin" / "python"
        if not candidate.is_file():
            raise RobotParsingError(
                f"Environment Python not found at '{candidate}'",
            )
        return _absolute_keep_wrapper(candidate)
