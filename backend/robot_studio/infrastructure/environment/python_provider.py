"""Python virtual environment operations via stdlib venv + subprocess."""

from __future__ import annotations

import logging
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import venv
from dataclasses import dataclass
from pathlib import Path

from robot_studio.infrastructure.environment.filesystem import (
    EnvironmentValidationError,
)

_VERSION_RE = re.compile(r"(\d+\.\d+(?:\.\d+)?)")
_SIDECAR_NAMES = frozenset(
    {
        "robot-studio-backend",
        "robot-studio-backend.exe",
    },
)


def stable_subprocess_cwd(preferred: Path | str | None = None) -> str:
    """Return an existing directory safe to pass as subprocess ``cwd``.

    Pip (and some other entry points) call ``os.getcwd()``. If this process's
    cwd was deleted — e.g. a project folder removed while the backend was
    still running — child pip processes crash with a confusing traceback.
    """
    candidates: list[Path] = []
    if preferred is not None:
        candidates.append(Path(preferred))
    try:
        candidates.append(Path.cwd())
    except OSError:
        pass
    candidates.extend([Path.home(), Path(tempfile.gettempdir())])
    for candidate in candidates:
        try:
            resolved = candidate.expanduser().resolve()
            if resolved.is_dir() and os.access(resolved, os.R_OK | os.X_OK):
                return str(resolved)
        except OSError:
            continue
    return tempfile.gettempdir()


def _is_bundled_sidecar(path: Path) -> bool:
    name = path.name.lower()
    return name in _SIDECAR_NAMES


def _windows_no_window_kwargs() -> dict:
    """Avoid flashing consoles / hanging UI when probing from the sidecar."""
    if sys.platform != "win32":
        return {}
    # CREATE_NO_WINDOW = 0x08000000
    return {"creationflags": getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)}


def _is_windows_apps_alias(path: Path) -> bool:
    """Microsoft Store execution aliases are 0-byte stubs under WindowsApps."""
    text = str(path).lower()
    if "windowsapps" not in text:
        return False
    try:
        return path.stat().st_size == 0
    except OSError:
        return True


def _discovery_environ() -> dict[str, str]:
    """PATH for discovering host Python (helps Microsoft Store / user installs)."""
    env = os.environ.copy()
    extras: list[str] = []
    if sys.platform == "win32":
        local = os.environ.get("LOCALAPPDATA") or str(
            Path.home() / "AppData" / "Local",
        )
        extras.extend(
            [
                str(Path(local) / "Programs" / "Python"),
                str(Path(local) / "Python" / "bin"),
                str(Path(local) / "Microsoft" / "WindowsApps"),
                str(Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"),
            ],
        )
        # Nested python.org installs: .../Python/Python312
        programs = Path(local) / "Programs" / "Python"
        if programs.is_dir():
            try:
                for child in programs.iterdir():
                    if child.is_dir():
                        extras.append(str(child))
            except OSError:
                pass
    path_parts = extras + [
        p for p in env.get("PATH", "").split(os.pathsep) if p
    ]
    # Dedupe preserving order
    seen: set[str] = set()
    ordered: list[str] = []
    for part in path_parts:
        key = os.path.normcase(part)
        if key in seen:
            continue
        seen.add(key)
        ordered.append(part)
    env["PATH"] = os.pathsep.join(ordered)
    return env


def _where_all(name: str, *, env: dict[str, str]) -> list[Path]:
    if sys.platform != "win32":
        return []
    try:
        result = subprocess.run(
            ["where.exe", name],
            capture_output=True,
            text=True,
            check=False,
            timeout=3,
            cwd=stable_subprocess_cwd(),
            env=env,
            **_windows_no_window_kwargs(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if result.returncode != 0:
        return []
    paths: list[Path] = []
    for line in (result.stdout or "").splitlines():
        line = line.strip().strip('"')
        if line:
            paths.append(Path(line))
    return paths


def _py_launcher_paths(env: dict[str, str]) -> list[Path]:
    """Resolve real interpreter paths via Windows `py` / `pymanager`.

    App execution aliases alone are not a runtime — users still need
    ``py install 3`` (or python.org). When a runtime exists, these commands
    return the real ``python.exe`` path.
    """
    if sys.platform != "win32":
        return []
    local = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    launcher_candidates = [
        shutil.which("pymanager", path=env.get("PATH")),
        shutil.which("py", path=env.get("PATH")),
        str(Path(local) / "Programs" / "Python" / "Launcher" / "py.exe"),
        str(Path(os.environ.get("SystemRoot", r"C:\Windows")) / "py.exe"),
        str(Path(local) / "Microsoft" / "WindowsApps" / "pymanager.exe"),
        str(Path(local) / "Microsoft" / "WindowsApps" / "py.exe"),
    ]
    launchers: list[str] = []
    seen: set[str] = set()
    for candidate in launcher_candidates:
        if not candidate:
            continue
        key = os.path.normcase(candidate)
        if key in seen:
            continue
        if not Path(candidate).is_file():
            continue
        seen.add(key)
        launchers.append(candidate)
    if not launchers:
        return []

    found: list[Path] = []

    def _run(argv: list[str]) -> subprocess.CompletedProcess[str] | None:
        try:
            return subprocess.run(
                argv,
                capture_output=True,
                text=True,
                check=False,
                timeout=5,
                cwd=stable_subprocess_cwd(),
                env=env,
                **_windows_no_window_kwargs(),
            )
        except (OSError, subprocess.TimeoutExpired):
            return None

    def _collect_paths_from_output(stdout: str) -> None:
        for line in (stdout or "").splitlines():
            line = line.strip().strip('"')
            if not line:
                continue
            # Legacy ``py -0p``: " -V:3.12 *  C:\\...\\python.exe"
            # ``py list -f=exe``: one path per line
            # table rows often end with a path
            if line.lower().endswith("python.exe") or line.lower().endswith("python3.exe"):
                found.append(Path(line.split()[-1].strip('"')))
                continue
            parts = line.split()
            if parts and parts[-1].lower().endswith(".exe"):
                found.append(Path(parts[-1].strip('"')))

    for launcher in launchers:
        # New install manager: list installed runtime executables.
        for argv in (
            [launcher, "list", "-f=exe"],
            [launcher, "list", "--format=exe"],
            [launcher, "-0p"],
            [launcher, "--list-paths"],
        ):
            result = _run(argv)
            if result is not None and result.returncode == 0 and (result.stdout or "").strip():
                _collect_paths_from_output(result.stdout or "")
                break

        # Launch default 3.x and print its real executable (may install on first run —
        # keep timeout short; failure is fine).
        for argv in (
            [launcher, "exec", "-3", "-c", "import sys; print(sys.executable)"],
            [launcher, "-3", "-c", "import sys; print(sys.executable)"],
        ):
            result = _run(argv)
            if result is not None and result.returncode == 0:
                line = (result.stdout or "").strip().splitlines()
                if line:
                    found.append(Path(line[-1].strip().strip('"')))
                    break

    # Managed aliases after ``py install`` (optional PATH dir).
    python_root = Path(local) / "Python"
    bin_dir = python_root / "bin"
    if bin_dir.is_dir():
        try:
            found.extend(bin_dir.glob("python*.exe"))
        except OSError:
            pass
    # PyManager runtime roots: ...\Python\pythoncore-3.14-64\python.exe
    if python_root.is_dir():
        try:
            found.extend(python_root.glob("pythoncore-*/python.exe"))
        except OSError:
            pass

    return found


def _windows_registry_pythons() -> list[Path]:
    """PEP 514 registration — all companies under Software\\Python."""
    if sys.platform != "win32":
        return []
    try:
        import winreg
    except ImportError:
        return []

    found: list[Path] = []
    root_keys = (
        (winreg.HKEY_CURRENT_USER, r"Software\Python"),
        (winreg.HKEY_LOCAL_MACHINE, r"Software\Python"),
        (winreg.HKEY_LOCAL_MACHINE, r"Software\Wow6432Node\Python"),
    )
    for hive, python_root in root_keys:
        try:
            with winreg.OpenKey(hive, python_root) as root:
                company_i = 0
                while True:
                    try:
                        company = winreg.EnumKey(root, company_i)
                    except OSError:
                        break
                    company_i += 1
                    try:
                        with winreg.OpenKey(root, company) as company_key:
                            tag_i = 0
                            while True:
                                try:
                                    tag = winreg.EnumKey(company_key, tag_i)
                                except OSError:
                                    break
                                tag_i += 1
                                try:
                                    with winreg.OpenKey(
                                        company_key, rf"{tag}\InstallPath"
                                    ) as install:
                                        try:
                                            exe, _ = winreg.QueryValueEx(
                                                install, "ExecutablePath"
                                            )
                                            if exe:
                                                found.append(Path(str(exe)))
                                                continue
                                        except OSError:
                                            pass
                                        try:
                                            base, _ = winreg.QueryValueEx(install, None)
                                            if base:
                                                found.append(
                                                    Path(str(base)) / "python.exe"
                                                )
                                        except OSError:
                                            pass
                                except OSError:
                                    continue
                    except OSError:
                        continue
        except OSError:
            continue
    return found


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


@dataclass(frozen=True)
class DiscoveredInterpreter:
    path: str
    version: str
    display_name: str


class PythonEnvironmentProvider:
    def create_venv(self, python_executable: Path, target_dir: Path) -> None:
        python = self._resolve_base_python(python_executable)
        if target_dir.exists() and any(target_dir.iterdir()):
            raise EnvironmentValidationError(
                f"Environment directory is not empty: '{target_dir}'",
            )

        # Prefer the selected interpreter so the venv matches the chosen version.
        if Path(python).resolve() == Path(sys.executable).resolve():
            try:
                builder = venv.EnvBuilder(
                    with_pip=True,
                    clear=False,
                    upgrade_deps=False,
                )
                builder.create(target_dir)
            except Exception as exc:
                raise EnvironmentValidationError(
                    f"Failed to create virtual environment: {exc}",
                ) from exc
            return

        result = subprocess.run(
            [str(python), "-m", "venv", str(target_dir)],
            capture_output=True,
            text=True,
            check=False,
            cwd=stable_subprocess_cwd(target_dir.parent),
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
            [
                str(python_executable),
                "-c",
                (
                    "import sys; v = sys.version_info; "
                    "print(f'{v.major}.{v.minor}.{v.micro}')"
                ),
            ],
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
            cwd=stable_subprocess_cwd(python_executable.parent),
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
            cwd=stable_subprocess_cwd(python_executable.parent),
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
                (
                    "import platform, sys; "
                    "print(sys.platform); print(platform.machine())"
                ),
            ],
            capture_output=True,
            text=True,
            check=False,
            cwd=stable_subprocess_cwd(python_executable.parent),
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
        # Prefer the venv root (…/bin/../ or …/Scripts/../) so pip has a
        # writable, existing cwd even when the backend's own cwd is gone.
        preferred = python_executable.resolve().parent.parent
        result = subprocess.run(
            [str(python_executable), "-m", "pip", "install", "robotframework"],
            capture_output=True,
            text=True,
            check=False,
            cwd=stable_subprocess_cwd(preferred),
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
            cwd=stable_subprocess_cwd(python_executable.parent),
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
            cwd=stable_subprocess_cwd(python_executable.resolve().parent.parent),
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

    def discover_interpreters(self) -> list[DiscoveredInterpreter]:
        """Find usable host Python interpreters for creating virtualenvs."""
        try:
            found = self._discover_interpreters_impl()
            logging.getLogger(__name__).info(
                "Discovered %s host Python interpreter(s)",
                len(found),
            )
            return found
        except Exception:
            logging.getLogger(__name__).exception(
                "Host Python discovery failed",
            )
            # Never 500 the UI — empty list shows install guidance instead.
            return []

    def _discover_interpreters_impl(self) -> list[DiscoveredInterpreter]:
        candidates: list[Path] = []
        seen_paths: set[str] = set()

        def add(path: Path | str | None) -> None:
            if path is None:
                return
            raw = Path(str(path).strip().strip('"')).expanduser()
            if _is_bundled_sidecar(raw):
                return
            # Never probe Store execution aliases — they hang or open the Store UI.
            if _is_windows_apps_alias(raw):
                return
            try:
                if not raw.is_file():
                    return
            except OSError:
                return
            key = os.path.normcase(os.path.abspath(str(raw)))
            if key in seen_paths:
                return
            seen_paths.add(key)
            candidates.append(Path(key))

        # Host Python only — never offer the frozen sidecar as a venv base.
        if not getattr(sys, "frozen", False):
            add(sys.executable)

        discovery_env = _discovery_environ()

        if sys.platform == "win32":
            # Fast paths first: py launcher + registry (covers Store + python.org).
            for path in _py_launcher_paths(discovery_env):
                add(path)
            for path in _windows_registry_pythons():
                add(path)
            for name in ("python", "python3"):
                which = shutil.which(name, path=discovery_env.get("PATH"))
                if which:
                    add(which)
                for found in _where_all(name, env=discovery_env):
                    add(found)
            local_app = Path(
                os.environ.get("LOCALAPPDATA")
                or (Path.home() / "AppData" / "Local"),
            )
            for directory in (
                Path(r"C:\Python310"),
                Path(r"C:\Python311"),
                Path(r"C:\Python312"),
                Path(r"C:\Python313"),
                local_app / "Programs" / "Python",
                local_app / "Python",
            ):
                if not directory.is_dir():
                    continue
                try:
                    for match in directory.glob("Python*/python.exe"):
                        add(match)
                    for match in directory.glob("pythoncore-*/python.exe"):
                        add(match)
                    add(directory / "python.exe")
                    add(directory / "bin" / "python.exe")
                except OSError:
                    continue
        else:
            for name in (
                "python3",
                "python",
                "python3.13",
                "python3.12",
                "python3.11",
                "python3.10",
                "python3.9",
            ):
                which = shutil.which(name, path=discovery_env.get("PATH"))
                if which:
                    add(which)
            for directory in (
                Path("/usr/bin"),
                Path("/usr/local/bin"),
                Path("/opt/homebrew/bin"),
                Path("/opt/local/bin"),
            ):
                if not directory.is_dir():
                    continue
                try:
                    for match in directory.glob("python3*"):
                        add(match)
                except OSError:
                    continue

        for base, pattern in (
            (Path.home() / ".pyenv" / "versions", "*/bin/python"),
            (
                Path.home() / ".local" / "share" / "mise" / "installs" / "python",
                "*/bin/python",
            ),
            (Path.home() / ".asdf" / "installs" / "python", "*/bin/python"),
        ):
            if base.is_dir():
                for match in base.glob(pattern):
                    add(match)

        discovered: dict[str, DiscoveredInterpreter] = {}
        # Cap probes so a bad PATH cannot stall Create Environment for minutes.
        probe_budget = 8 if sys.platform == "win32" else 20
        probed = 0
        for candidate in candidates:
            if probed >= probe_budget:
                break
            if _is_bundled_sidecar(candidate) or _is_windows_apps_alias(candidate):
                continue
            key = os.path.normcase(str(candidate))
            if key in discovered:
                continue
            if sys.platform != "win32" and not os.access(candidate, os.X_OK):
                continue
            probed += 1
            version = self._probe_version(candidate)
            if version is None:
                continue
            display_path = str(candidate)
            display = f"Python {version} — {display_path}"
            discovered[key] = DiscoveredInterpreter(
                path=display_path,
                version=version,
                display_name=display,
            )

        def sort_key(item: DiscoveredInterpreter) -> tuple:
            parts = []
            for piece in item.version.split("."):
                try:
                    parts.append(int(piece))
                except ValueError:
                    parts.append(0)
            while len(parts) < 3:
                parts.append(0)
            apps_penalty = 1 if "windowsapps" in item.path.lower() else 0
            return (-parts[0], -parts[1], -parts[2], apps_penalty, item.path)

        return sorted(discovered.values(), key=sort_key)

    def _probe_version(self, python_executable: Path) -> str | None:
        timeout = 2
        try:
            result = subprocess.run(
                [
                    str(python_executable),
                    "-c",
                    (
                        "import sys; "
                        "print(f'{sys.version_info.major}."
                        "{sys.version_info.minor}.{sys.version_info.micro}')"
                    ),
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=timeout,
                cwd=stable_subprocess_cwd(),
                env=_discovery_environ(),
                **_windows_no_window_kwargs(),
            )
        except (OSError, subprocess.TimeoutExpired):
            return None
        if result.returncode != 0:
            return None
        version = (result.stdout or "").strip().splitlines()
        version = version[-1].strip() if version else ""
        if not _VERSION_RE.fullmatch(version):
            return None
        return version

    def _run(self, command: list[str], *, error_prefix: str) -> str:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            cwd=stable_subprocess_cwd(),
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "command failed").strip()
            raise EnvironmentValidationError(f"{error_prefix}: {detail}")
        return (result.stdout or "").strip()
