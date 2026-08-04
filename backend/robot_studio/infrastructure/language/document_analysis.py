"""Document intelligence — sole owner of buffer → DocumentSymbolTree analysis.

Outline, breadcrumbs, folding, and future navigation are read-only consumers.
Callers must not invoke the parsing worker for document symbols directly.
"""

from __future__ import annotations

import hashlib
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from pathlib import Path

from robot_studio.domain.models.document_symbols import (
    DocumentSymbol,
    DocumentSymbolTree,
)

RunSymbolTree = Callable[[str, str], Awaitable[dict]]


@dataclass
class DocumentAnalysisService:
    """Canonical cache for live document symbol trees."""

    _run_tree: RunSymbolTree
    _cache: dict[str, DocumentSymbolTree] = field(default_factory=dict, init=False)
    _max_entries: int = 64

    def invalidate(self, file_path: str | None = None) -> None:
        if file_path is None:
            self._cache.clear()
            return
        prefix = f"{file_path}:"
        for key in list(self._cache):
            if key.startswith(prefix) or key == file_path:
                del self._cache[key]

    @staticmethod
    def content_hash(content: str) -> str:
        return hashlib.sha1(content.encode("utf-8")).hexdigest()[:16]

    async def analyze(self, file_path: str, content: str) -> DocumentSymbolTree:
        path = file_path or "file.robot"
        digest = self.content_hash(content)
        cache_key = f"{path}:{digest}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        raw = await self._run_tree(content, path)
        if not isinstance(raw, dict):
            raw = {}
        root_raw = raw.get("root") if isinstance(raw.get("root"), dict) else None
        if root_raw is None:
            root = DocumentSymbol(
                name=Path(path).stem or Path(path).name,
                kind="test_suite",
                line=1,
                end_line=1,
            )
        else:
            root = DocumentSymbol.from_api(root_raw)

        tree = DocumentSymbolTree(
            file_path=str(raw.get("file_path") or path),
            root=root,
            content_hash=digest,
        )
        self._put(cache_key, tree)
        return tree

    async def analyze_path(self, file_path: str) -> DocumentSymbolTree:
        """Analyze on-disk content (Outline fallback when buffer unavailable)."""
        path = Path(file_path)
        content = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""
        return await self.analyze(str(path), content)

    def _put(self, key: str, tree: DocumentSymbolTree) -> None:
        if key in self._cache:
            self._cache[key] = tree
            return
        if len(self._cache) >= self._max_entries:
            # Drop oldest insertion (dict preserves order on 3.7+).
            oldest = next(iter(self._cache))
            del self._cache[oldest]
        self._cache[key] = tree
