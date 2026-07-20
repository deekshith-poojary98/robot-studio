"""Lightweight Python Robot library keyword extraction."""

from __future__ import annotations

import ast
import hashlib
from pathlib import Path
from uuid import UUID

from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import IndexedSymbol


def _sid(kind: str, file_path: Path, name: str, line: int) -> str:
    raw = f"{kind}:{file_path}:{name}:{line}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:24]


class PythonLibraryIndexer:
    """Indexes def-level keywords from Python library modules."""

    INDEXABLE_SUFFIXES = {".py"}

    def index_file(
        self,
        path: Path,
        *,
        workspace_id: UUID | None,
        project_id: UUID | None,
    ) -> list[IndexedSymbol]:
        if path.name.startswith("_") or path.name == "__init__.py":
            # Still index keywords from __init__ if present; skip underscore modules.
            if path.name.startswith("_") and path.name != "__init__.py":
                return []

        try:
            source = path.read_text(encoding="utf-8", errors="replace")
            tree = ast.parse(source, filename=str(path))
        except (SyntaxError, OSError):
            return []

        mtime = path.stat().st_mtime
        symbols: list[IndexedSymbol] = [
            IndexedSymbol(
                id=_sid(SymbolKind.LIBRARY.value, path, path.stem, 1),
                name=path.stem,
                kind=SymbolKind.LIBRARY.value,
                file_path=path,
                line=1,
                project_id=project_id,
                workspace_id=workspace_id,
                detail="python",
                last_modified=mtime,
            ),
            IndexedSymbol(
                id=_sid(SymbolKind.FILE.value, path, path.name, 1),
                name=path.name,
                kind=SymbolKind.FILE.value,
                file_path=path,
                line=1,
                project_id=project_id,
                workspace_id=workspace_id,
                detail="py",
                last_modified=mtime,
            ),
        ]

        for node in tree.body:
            if isinstance(node, ast.FunctionDef) and not node.name.startswith("_"):
                if self._looks_like_keyword(node):
                    symbols.append(self._keyword_symbol(path, node, workspace_id, project_id, mtime))
            elif isinstance(node, ast.ClassDef):
                for item in node.body:
                    if isinstance(item, ast.FunctionDef) and not item.name.startswith("_"):
                        if self._looks_like_keyword(item):
                            symbols.append(
                                self._keyword_symbol(
                                    path,
                                    item,
                                    workspace_id,
                                    project_id,
                                    mtime,
                                    library=node.name,
                                ),
                            )
        return symbols

    def _keyword_symbol(
        self,
        path: Path,
        node: ast.FunctionDef,
        workspace_id: UUID | None,
        project_id: UUID | None,
        mtime: float,
        *,
        library: str | None = None,
    ) -> IndexedSymbol:
        args = [arg.arg for arg in node.args.args if arg.arg != "self"]
        doc = ast.get_docstring(node) or ""
        return IndexedSymbol(
            id=_sid(SymbolKind.KEYWORD.value, path, node.name, node.lineno),
            name=node.name.replace("_", " "),
            kind=SymbolKind.KEYWORD.value,
            file_path=path,
            line=node.lineno,
            project_id=project_id,
            workspace_id=workspace_id,
            documentation=doc,
            detail=", ".join(args) if args else (library or "python"),
            last_modified=mtime,
        )

    @staticmethod
    def _looks_like_keyword(node: ast.FunctionDef) -> bool:
        for decorator in node.decorator_list:
            name = ""
            if isinstance(decorator, ast.Name):
                name = decorator.id
            elif isinstance(decorator, ast.Attribute):
                name = decorator.attr
            elif isinstance(decorator, ast.Call):
                if isinstance(decorator.func, ast.Name):
                    name = decorator.func.id
                elif isinstance(decorator.func, ast.Attribute):
                    name = decorator.func.attr
            if name.lower() in {"keyword", "robotkeyword"}:
                return True
        return False
