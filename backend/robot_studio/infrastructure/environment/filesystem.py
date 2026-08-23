"""Filesystem layout and environment.json manifest helpers."""

from __future__ import annotations

import json
import re
import shutil
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

from robot_studio.infrastructure.workspace.filesystem import (
    legacy_environments_root,
    studio_environments_root,
)

ENVIRONMENT_MANIFEST = "environment.json"
# Back-compat alias for older imports / docs.
ENVIRONMENTS_DIR = "environments"

_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


class EnvironmentValidationError(Exception):
    """Raised when environment filesystem operations fail validation."""


@dataclass(frozen=True)
class EnvironmentManifest:
    id: UUID
    name: str
    python_version: str
    python_executable: Path
    pip_executable: Path
    robot_executable: Path | None
    path: Path
    created_at: datetime
    active: bool

    def to_dict(self) -> dict:
        return {
            "id": str(self.id),
            "name": self.name,
            "python_version": self.python_version,
            "python_executable": str(self.python_executable),
            "pip_executable": str(self.pip_executable),
            "robot_executable": (
                str(self.robot_executable) if self.robot_executable else None
            ),
            "path": str(self.path),
            "created_at": self.created_at.isoformat(),
            "active": self.active,
        }

    @classmethod
    def from_dict(cls, data: dict) -> EnvironmentManifest:
        created_raw = data["created_at"]
        created_at = (
            datetime.fromisoformat(created_raw)
            if isinstance(created_raw, str)
            else created_raw
        )
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=UTC)

        robot_raw = data.get("robot_executable")
        return cls(
            id=UUID(str(data["id"])),
            name=str(data["name"]),
            python_version=str(data["python_version"]),
            python_executable=Path(str(data["python_executable"])),
            pip_executable=Path(str(data["pip_executable"])),
            robot_executable=Path(str(robot_raw)) if robot_raw else None,
            path=Path(str(data["path"])),
            created_at=created_at,
            active=bool(data.get("active", False)),
        )


class FilesystemEnvironmentProvider:
    def environments_root(self, workspace_root: Path) -> Path:
        """Canonical write location: ``.robotstudio/environments``."""
        return studio_environments_root(workspace_root)

    def environments_roots(self, workspace_root: Path) -> list[Path]:
        """Canonical + legacy roots (for discovery / existence checks)."""
        roots = [self.environments_root(workspace_root)]
        legacy = legacy_environments_root(workspace_root)
        if legacy.resolve() not in {path.resolve() for path in roots}:
            roots.append(legacy)
        return roots

    def environment_root_for_name(self, workspace_root: Path, name: str) -> Path:
        """Path for a *new* environment under the canonical root."""
        cleaned = self.validate_name(name)
        return self.environments_root(workspace_root) / cleaned

    def find_existing_environment_root(
        self,
        workspace_root: Path,
        name: str,
    ) -> Path | None:
        """Return an existing env dir in canonical or legacy roots, if any."""
        cleaned = self.validate_name(name)
        for root in self.environments_roots(workspace_root):
            candidate = root / cleaned
            if candidate.exists():
                return candidate
        return None

    def validate_name(self, name: str) -> str:
        cleaned = name.strip()
        if not cleaned:
            raise EnvironmentValidationError("Environment name is required")
        if not _NAME_PATTERN.fullmatch(cleaned):
            raise EnvironmentValidationError(
                "Environment name must start with a letter or digit and contain "
                "only letters, digits, dots, underscores, or hyphens",
            )
        return cleaned

    def suggested_name(self, environment_root: Path) -> str:
        """Registry display name for an on-disk venv folder.

        Common project folders like ``.venv`` start with a dot, which is
        invalid as a Studio environment name. Strip leading dots so import
        and detection agree (``.venv`` → ``venv``).
        """
        raw = environment_root.name.strip()
        cleaned = raw.lstrip(".") or raw
        return self.validate_name(cleaned)

    def manifest_path(self, environment_root: Path) -> Path:
        return environment_root / ENVIRONMENT_MANIFEST

    def has_manifest(self, environment_root: Path) -> bool:
        return self.manifest_path(environment_root).is_file()

    def load_manifest(self, environment_root: Path) -> EnvironmentManifest:
        path = self.manifest_path(environment_root)
        if not path.is_file():
            raise EnvironmentValidationError(
                f"Missing {ENVIRONMENT_MANIFEST} in '{environment_root}'",
            )
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            return EnvironmentManifest.from_dict(raw)
        except (json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
            raise EnvironmentValidationError(
                f"Invalid environment manifest at '{path}': {exc}",
            ) from exc

    def write_manifest(
        self,
        environment_root: Path,
        manifest: EnvironmentManifest,
    ) -> None:
        environment_root.mkdir(parents=True, exist_ok=True)
        target = self.manifest_path(environment_root)
        target.write_text(
            json.dumps(manifest.to_dict(), indent=2) + "\n",
            encoding="utf-8",
        )

    def create_manifest(
        self,
        *,
        name: str,
        python_version: str,
        python_executable: Path,
        pip_executable: Path,
        robot_executable: Path | None,
        path: Path,
        active: bool = False,
        environment_id: UUID | None = None,
        created_at: datetime | None = None,
    ) -> EnvironmentManifest:
        return EnvironmentManifest(
            id=environment_id or uuid4(),
            name=name,
            python_version=python_version,
            python_executable=python_executable,
            pip_executable=pip_executable,
            robot_executable=robot_executable,
            path=path.resolve(),
            created_at=created_at or datetime.now(UTC),
            active=active,
        )

    def is_virtualenv(self, path: Path) -> bool:
        return (path / "pyvenv.cfg").is_file()

    def discover(self, workspace_root: Path) -> list[Path]:
        """List Studio-managed venvs under canonical and legacy roots."""
        found: list[Path] = []
        seen: set[Path] = set()
        for root in self.environments_roots(workspace_root):
            if not root.is_dir():
                continue
            for child in root.iterdir():
                if not child.is_dir() or not self.is_virtualenv(child):
                    continue
                resolved = child.resolve()
                if resolved in seen:
                    continue
                seen.add(resolved)
                found.append(child)
        return sorted(found, key=lambda item: item.name.lower())

    def discover_candidates(self, project_root: Path) -> list[Path]:
        """Find local virtualenvs users commonly keep beside a project."""
        root = project_root.expanduser().resolve()
        found: list[Path] = []
        seen: set[Path] = set()

        def _add(path: Path) -> None:
            resolved = path.resolve()
            if resolved in seen or not resolved.is_dir():
                return
            if self.is_virtualenv(resolved):
                seen.add(resolved)
                found.append(resolved)

        for name in (".venv", "venv", "env"):
            _add(root / name)

        for path in self.discover(root):
            _add(path)

        return found

    def delete_directory(self, environment_root: Path) -> None:
        if environment_root.exists():
            shutil.rmtree(environment_root)
