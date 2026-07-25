"""Workspace-scoped filesystem helpers for the editor."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import EventBus, FileWritten

_SKIP_NAMES = {
    "__pycache__",
    ".venv",
    "venv",
    ".git",
    "node_modules",
    "site-packages",
    "dist-info",
}

_VENV_INTERNAL = {"bin", "lib", "include", "share", "scripts", "lib64"}


class FileValidationError(Exception):
    """Raised when a file operation is invalid."""


@dataclass
class FileService:
    context: WorkspaceContext
    event_bus: EventBus | None = None

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
        if self.event_bus is not None:
            await self.event_bus.publish(FileWritten(path=str(target)))
        return {
            "path": str(target),
            "mtime": stat.st_mtime,
            "size": stat.st_size,
            "saved_at": datetime.now(UTC).isoformat(),
        }

    async def list_tree(self, path: str | None = None, *, depth: int = 0) -> list[dict]:
        """List directory entries.

        *depth=0* (default) is VS Code style: only immediate children, no recursion.
        Callers expand folders with a follow-up request for that path.
        """
        workspace = self._require_workspace()
        root = self._resolve_under_workspace(path) if path else workspace.path
        if not root.exists():
            raise FileValidationError(f"Path not found: {root}")
        return await asyncio.to_thread(self._walk, root, depth, workspace.path)

    def _should_skip(self, child: Path, relative_to: Path) -> bool:
        if child.name in _SKIP_NAMES or child.name.startswith("."):
            return True
        if child.name.endswith(".dist-info"):
            return True
        try:
            rel_parts = child.relative_to(relative_to).parts
        except ValueError:
            rel_parts = child.parts
        if "Environments" in rel_parts:
            env_index = rel_parts.index("Environments")
            if (
                len(rel_parts) >= env_index + 3
                and rel_parts[env_index + 2].lower() in _VENV_INTERNAL
            ):
                return True
            if len(rel_parts) > env_index + 3:
                return True
        return False

    def _dir_has_children(self, directory: Path, relative_to: Path) -> bool:
        try:
            for child in directory.iterdir():
                if not self._should_skip(child, relative_to):
                    return True
        except OSError:
            return False
        return False

    def _walk(self, root: Path, depth: int, relative_to: Path) -> list[dict]:
        if depth < 0 or not root.is_dir():
            return []
        try:
            children = sorted(
                root.iterdir(),
                key=lambda p: (not p.is_dir(), p.name.lower()),
            )
        except OSError:
            return []

        entries: list[dict] = []
        for child in children:
            if self._should_skip(child, relative_to):
                continue
            try:
                rel_parts = child.relative_to(relative_to).parts
            except ValueError:
                rel_parts = child.parts
            is_dir = child.is_dir()
            item: dict = {
                "name": child.name,
                "path": str(child),
                "relative_path": str(child.relative_to(relative_to)),
                "is_dir": is_dir,
                "suffix": child.suffix.lower(),
                "has_children": False,
                "children": [],
            }
            if is_dir:
                stop_at_env = (
                    "Environments" in rel_parts
                    and len(rel_parts) == rel_parts.index("Environments") + 2
                )
                if stop_at_env:
                    item["has_children"] = False
                elif depth > 0:
                    nested = self._walk(child, depth - 1, relative_to)
                    item["children"] = nested
                    item["has_children"] = bool(nested)
                else:
                    item["has_children"] = self._dir_has_children(child, relative_to)
            entries.append(item)
        return entries
