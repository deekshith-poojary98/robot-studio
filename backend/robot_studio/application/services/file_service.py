"""Workspace-scoped filesystem helpers for the editor."""

from __future__ import annotations

import asyncio
import re
import shutil
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import EventBus, FileWritten, FilesystemChanged

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

_INVALID_CHARS = re.compile(r'[<>:"|?*\x00-\x1f]')
_WINDOWS_RESERVED = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}

# Seeded into newly created empty ``*.robot`` suite files.
DEFAULT_ROBOT_SUITE_CONTENT = """\
*** Settings ***
Documentation    Test suite description
Library          BuiltIn

*** Variables ***

*** Test Cases ***
Example Test
    [Documentation]    Example test case
    Log    Hello, Robot Framework!

*** Keywords ***
Example Keyword
    [Documentation]    Example reusable keyword
    Log    Keyword executed
"""


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

    @staticmethod
    def validate_entry_name(name: str) -> str:
        cleaned = name.strip()
        if not cleaned:
            raise FileValidationError("Name cannot be empty")
        if cleaned != name:
            raise FileValidationError("Name cannot start or end with spaces")
        if cleaned in {".", ".."}:
            raise FileValidationError("Name is not allowed")
        if "/" in cleaned or "\\" in cleaned:
            raise FileValidationError("Name cannot contain path separators")
        if _INVALID_CHARS.search(cleaned):
            raise FileValidationError('Name contains invalid characters (<>:"|?*)')
        if cleaned.endswith(".") or cleaned.endswith(" "):
            raise FileValidationError("Name cannot end with a dot or space")
        stem = cleaned.split(".")[0].upper()
        if stem in _WINDOWS_RESERVED:
            raise FileValidationError(f"'{cleaned}' is a reserved name")
        return cleaned

    async def _publish_fs(
        self,
        kind: str,
        path: Path,
        *,
        old_path: Path | None = None,
        is_directory: bool = False,
    ) -> None:
        if self.event_bus is None:
            return
        await self.event_bus.publish(
            FilesystemChanged(
                kind=kind,
                path=str(path),
                old_path=str(old_path) if old_path is not None else None,
                is_directory=is_directory,
            )
        )

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
        created = not target.exists()
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        stat = target.stat()
        if self.event_bus is not None:
            await self.event_bus.publish(FileWritten(path=str(target)))
            await self._publish_fs(
                "FILE_CREATED" if created else "FILE_MODIFIED",
                target,
            )
        return {
            "path": str(target),
            "mtime": stat.st_mtime,
            "size": stat.st_size,
            "saved_at": datetime.now(UTC).isoformat(),
        }

    async def create_file(self, path: str, content: str = "") -> dict:
        target = self._resolve_under_workspace(path)
        self.validate_entry_name(target.name)
        if target.exists():
            raise FileValidationError(f"'{target.name}' already exists")
        target.parent.mkdir(parents=True, exist_ok=True)
        body = content
        if not body and target.suffix.lower() == ".robot":
            body = DEFAULT_ROBOT_SUITE_CONTENT
        target.write_text(body, encoding="utf-8")
        stat = target.stat()
        if self.event_bus is not None:
            await self.event_bus.publish(FileWritten(path=str(target)))
            await self._publish_fs("FILE_CREATED", target)
        return {
            "path": str(target),
            "mtime": stat.st_mtime,
            "size": stat.st_size,
            "saved_at": datetime.now(UTC).isoformat(),
        }

    async def create_directory(self, path: str) -> dict:
        target = self._resolve_under_workspace(path)
        self.validate_entry_name(target.name)
        if target.exists():
            raise FileValidationError(f"'{target.name}' already exists")
        target.mkdir(parents=True, exist_ok=False)
        await self._publish_fs("DIRECTORY_CREATED", target, is_directory=True)
        return {
            "path": str(target),
            "is_dir": True,
            "name": target.name,
        }

    async def rename_path(self, path: str, new_name: str) -> dict:
        source = self._resolve_under_workspace(path)
        if not source.exists():
            raise FileValidationError(f"Path not found: {path}")
        cleaned = self.validate_entry_name(new_name)
        destination = source.with_name(cleaned)
        destination = self._resolve_under_workspace(destination)
        # Same-name rename (Enter without changing) is a no-op — destination
        # already "exists" because it is the source path.
        if source.resolve() == destination.resolve() or (
            destination.exists() and source.samefile(destination)
        ):
            return {
                "path": str(source),
                "old_path": str(source),
                "is_dir": source.is_dir(),
                "name": source.name,
            }
        if destination.exists():
            raise FileValidationError(f"'{cleaned}' already exists")
        is_dir = source.is_dir()
        source.rename(destination)
        kind = "DIRECTORY_RENAMED" if is_dir else "FILE_RENAMED"
        await self._publish_fs(
            kind,
            destination,
            old_path=source,
            is_directory=is_dir,
        )
        if not is_dir and self.event_bus is not None:
            await self.event_bus.publish(FileWritten(path=str(destination)))
        return {
            "path": str(destination),
            "old_path": str(source),
            "is_dir": is_dir,
            "name": destination.name,
        }

    async def move_path(self, path: str, destination_dir: str) -> dict:
        source = self._resolve_under_workspace(path)
        if not source.exists():
            raise FileValidationError(f"Path not found: {path}")
        dest_dir = self._resolve_under_workspace(destination_dir)
        if not dest_dir.is_dir():
            raise FileValidationError("Destination must be a folder")
        destination = dest_dir / source.name
        if destination.exists():
            raise FileValidationError(f"'{source.name}' already exists in the destination")
        # Prevent moving a folder into itself.
        if source.is_dir():
            try:
                dest_dir.resolve().relative_to(source.resolve())
                raise FileValidationError("Cannot move a folder into itself")
            except ValueError:
                pass
        is_dir = source.is_dir()
        shutil.move(str(source), str(destination))
        kind = "DIRECTORY_RENAMED" if is_dir else "FILE_RENAMED"
        await self._publish_fs(
            kind,
            destination,
            old_path=source,
            is_directory=is_dir,
        )
        if not is_dir and self.event_bus is not None:
            await self.event_bus.publish(FileWritten(path=str(destination)))
        return {
            "path": str(destination),
            "old_path": str(source),
            "is_dir": is_dir,
            "name": destination.name,
        }

    async def delete_path(self, path: str) -> dict:
        target = self._resolve_under_workspace(path)
        workspace = self._require_workspace()
        if target.resolve() == workspace.path.resolve():
            raise FileValidationError("Cannot delete the workspace root")
        if not target.exists():
            raise FileValidationError(f"Path not found: {path}")
        is_dir = target.is_dir()
        if is_dir:
            shutil.rmtree(target)
        else:
            target.unlink()
        kind = "DIRECTORY_DELETED" if is_dir else "FILE_DELETED"
        await self._publish_fs(kind, target, is_directory=is_dir)
        return {
            "path": str(target),
            "is_dir": is_dir,
            "deleted": True,
        }

    async def duplicate_path(self, path: str) -> dict:
        source = self._resolve_under_workspace(path)
        if not source.exists():
            raise FileValidationError(f"Path not found: {path}")
        destination = self._unique_copy_path(source)
        is_dir = source.is_dir()
        if is_dir:
            shutil.copytree(source, destination)
            await self._publish_fs("DIRECTORY_CREATED", destination, is_directory=True)
        else:
            shutil.copy2(source, destination)
            if self.event_bus is not None:
                await self.event_bus.publish(FileWritten(path=str(destination)))
            await self._publish_fs("FILE_CREATED", destination)
        return {
            "path": str(destination),
            "old_path": str(source),
            "is_dir": is_dir,
            "name": destination.name,
        }

    def _unique_copy_path(self, source: Path) -> Path:
        parent = source.parent
        stem = source.stem
        suffix = source.suffix
        if source.is_dir():
            stem = source.name
            suffix = ""
        candidate = parent / f"{stem} copy{suffix}"
        if not candidate.exists():
            return candidate
        index = 2
        while True:
            candidate = parent / f"{stem} copy {index}{suffix}"
            if not candidate.exists():
                return candidate
            index += 1

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
