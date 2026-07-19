"""Filesystem layout and workspace.json manifest helpers."""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

WORKSPACE_META_DIR = ".robotstudio"
WORKSPACE_MANIFEST = "workspace.json"
WORKSPACE_MARKER = Path(WORKSPACE_META_DIR) / WORKSPACE_MANIFEST

STANDARD_DIRECTORIES = (
    "Projects",
    "Shared/Resources",
    "Shared/Variables",
    "Environments",
    "Reports",
)


class WorkspaceValidationError(Exception):
    """Raised when a path is not a valid Robot Studio workspace."""


@dataclass(frozen=True)
class WorkspaceManifest:
    name: str
    version: int
    created_at: datetime
    projects: list[dict]

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "version": self.version,
            "created_at": self.created_at.isoformat(),
            "projects": self.projects,
        }

    @classmethod
    def from_dict(cls, data: dict) -> WorkspaceManifest:
        created_raw = data["created_at"]
        created_at = (
            datetime.fromisoformat(created_raw)
            if isinstance(created_raw, str)
            else created_raw
        )
        return cls(
            name=str(data["name"]),
            version=int(data.get("version", 1)),
            created_at=created_at,
            projects=list(data.get("projects", [])),
        )


def manifest_path(workspace_root: Path) -> Path:
    return workspace_root / WORKSPACE_MARKER


def is_workspace(path: Path) -> bool:
    return manifest_path(path).is_file()


def load_manifest(workspace_root: Path) -> WorkspaceManifest:
    path = manifest_path(workspace_root)
    if not path.is_file():
        raise WorkspaceValidationError(
            f"'{workspace_root}' is not a Robot Studio workspace "
            f"(missing {WORKSPACE_MARKER})",
        )
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        return WorkspaceManifest.from_dict(raw)
    except (json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
        raise WorkspaceValidationError(
            f"Invalid workspace manifest at '{path}': {exc}",
        ) from exc


def write_manifest(workspace_root: Path, manifest: WorkspaceManifest) -> None:
    meta_dir = workspace_root / WORKSPACE_META_DIR
    meta_dir.mkdir(parents=True, exist_ok=True)
    target = meta_dir / WORKSPACE_MANIFEST
    target.write_text(
        json.dumps(manifest.to_dict(), indent=2) + "\n",
        encoding="utf-8",
    )


def create_workspace_structure(workspace_root: Path, name: str) -> WorkspaceManifest:
    if workspace_root.exists() and any(workspace_root.iterdir()):
        if is_workspace(workspace_root):
            raise WorkspaceValidationError(
                f"A Robot Studio workspace already exists at '{workspace_root}'",
            )
        raise WorkspaceValidationError(
            f"Directory '{workspace_root}' is not empty",
        )

    workspace_root.mkdir(parents=True, exist_ok=True)

    for relative in STANDARD_DIRECTORIES:
        (workspace_root / relative).mkdir(parents=True, exist_ok=True)

    manifest = WorkspaceManifest(
        name=name,
        version=1,
        created_at=datetime.now(UTC),
        projects=[],
    )
    write_manifest(workspace_root, manifest)
    return manifest
