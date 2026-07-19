"""Workspace-scoped filesystem helpers for the editor."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from robot_studio.application.services.workspace_context import WorkspaceContext


class FileValidationError(Exception):
    """Raised when a file operation is invalid."""


@dataclass
class FileService:
    context: WorkspaceContext

    def _require_workspace(self):
        workspace = self.context.workspace
        if workspace is None:
            raise FileValidationError("Open a workspace before accessing files")
        return workspace

    def _resolve_under_workspace(self, path: str | Path) -> Path:
        workspace = self._require_workspace()
        target = Path(path).expanduser()
        if not target.is_absolute():
            target = workspace.path / target
        resolved = target.resolve()
        root = workspace.path.resolve()
        try:
            resolved.relative_to(root)
        except ValueError as exc:
            raise FileValidationError("Path is outside the active workspace") from exc
        return resolved

    async def read_file(self, path: str) -> dict:
        target = self._resolve_under_workspace(path)
        if not target.is_file():
            raise FileValidationError(f"File not found: {path}")
        try:
            content = target.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            content = target.read_text(encoding="utf-8", errors="replace")
        stat = target.stat()
        return {
            "path": str(target),
            "content": content,
            "mtime": stat.st_mtime,
            "size": stat.st_size,
        }

    async def write_file(self, path: str, content: str) -> dict:
        target = self._resolve_under_workspace(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        stat = target.stat()
        return {
            "path": str(target),
            "mtime": stat.st_mtime,
            "size": stat.st_size,
            "saved_at": datetime.now(UTC).isoformat(),
        }

    async def list_tree(self, path: str | None = None, *, depth: int = 3) -> list[dict]:
        workspace = self._require_workspace()
        root = self._resolve_under_workspace(path) if path else workspace.path
        if not root.exists():
            raise FileValidationError(f"Path not found: {root}")
        return self._walk(root, depth=depth, relative_to=workspace.path)

    def _walk(self, root: Path, *, depth: int, relative_to: Path) -> list[dict]:
        if depth < 0 or not root.is_dir():
            return []
        entries: list[dict] = []
        try:
            children = sorted(root.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
        except OSError:
            return []
        skip = {"__pycache__", ".venv", "venv", ".git", "node_modules"}
        for child in children:
            if child.name in skip or child.name.startswith("."):
                continue
            # Skip Environments venv internals for clearer explorer.
            if "Environments" in child.parts and child.suffix in {".so", ".dylib"}:
                continue
            item = {
                "name": child.name,
                "path": str(child),
                "relative_path": str(child.relative_to(relative_to)),
                "is_dir": child.is_dir(),
                "suffix": child.suffix.lower(),
            }
            if child.is_dir() and depth > 0:
                item["children"] = self._walk(child, depth=depth - 1, relative_to=relative_to)
            entries.append(item)
        return entries
