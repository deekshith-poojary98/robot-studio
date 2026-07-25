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


def find_workspace_root(path: Path) -> Path | None:
    """Walk *path* and its parents for a Robot Studio workspace root."""
    current = path.expanduser().resolve()
    if current.is_file():
        current = current.parent
    for candidate in (current, *current.parents):
        if is_workspace(candidate):
            return candidate
    return None


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


def initialize_project_as_workspace(
    project_root: Path,
    name: str | None = None,
) -> WorkspaceManifest:
    """Treat *project_root* as a single-project workspace.

    Creates only ``.robotstudio/workspace.json`` inside the project folder.
    Does **not** create ``Projects/``, ``Shared/``, or other wrapper directories.
    """
    root = project_root.expanduser().resolve()
    if not root.is_dir():
        raise WorkspaceValidationError(
            f"Directory does not exist: '{root}'",
        )
    if is_workspace(root):
        return load_manifest(root)

    display_name = (name or root.name).strip() or "Project"
    manifest = WorkspaceManifest(
        name=display_name,
        version=1,
        created_at=datetime.now(UTC),
        projects=[],
    )
    write_manifest(root, manifest)
    return manifest


def resolve_project_entry_path(workspace_root: Path, stored_path: str) -> Path:
    """Resolve a workspace.json project path entry to an absolute path."""
    raw = Path(stored_path)
    if raw.is_absolute():
        return raw.expanduser().resolve()
    return (workspace_root / raw).resolve()
