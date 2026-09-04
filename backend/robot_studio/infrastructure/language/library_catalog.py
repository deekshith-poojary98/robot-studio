"""Canonical semantic cache for Robot Framework libraries.

Sole owner of ``resolve_library`` discovery, caching, invalidation, and lazy
keyword loading. REST, Library Explorer, Completion, Signature Help, and Hover
are read-only consumers of ``LibraryMetadata`` / ``KeywordMetadata``.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from robot_studio.domain.models.keyword_metadata import (
    KeywordMetadata,
    KeywordSourceType,
)
from robot_studio.domain.models.library_metadata import LibraryMetadata

# resolve(name, file_path="") — file_path is the importing suite (for relative libs).
ResolveLibraryRaw = Callable[..., Awaitable[dict[str, Any]]]
# Each entry: (import_name, importing_file_path)
DiscoverImports = Callable[[], Awaitable[list[tuple[str, str]]]]


@dataclass
class LibraryCatalogService:
    """Single source of truth for library metadata in the language subsystem."""

    _resolve_raw: ResolveLibraryRaw
    _discover_imports: DiscoverImports
    _cache: dict[str, LibraryMetadata] = field(default_factory=dict, init=False)
    _membership_order: list[str] = field(default_factory=list, init=False)
    _membership_ready: bool = field(default=False, init=False)
    _membership_lock: asyncio.Lock = field(default_factory=asyncio.Lock, init=False)

    def invalidate(self) -> None:
        """Drop all cached instances (env / imports / index generation changed)."""
        self._cache.clear()
        self._membership_order.clear()
        self._membership_ready = False

    async def list_libraries(self, *, extra_imports: list[str] | None = None) -> list[LibraryMetadata]:
        """Return library summaries for Library Explorer.

        Re-syncs discovery on every list so ``Library`` imports from Robot
        files appear after save/reindex without requiring an app restart.
        """
        async with self._membership_lock:
            if not self._membership_ready:
                await self._ensure_membership(extra_imports=extra_imports)
            else:
                await self._sync_discovered_imports(extra_imports=extra_imports)
            return self._ordered_unique_libraries()

    async def get_library(self, name: str) -> LibraryMetadata | None:
        """Return the canonical instance for *name*, lazy-loading keywords once."""
        cleaned = (name or "").strip()
        if not cleaned:
            return None
        key = cleaned.casefold()
        existing = self._cache.get(key)
        # ``last_updated`` marks a completed resolve (including empty keyword
        # sets such as Remote with no live server). Summaries leave it unset.
        if existing is not None and (
            existing.keywords or existing.last_updated is not None
        ):
            return existing

        raw = await self._resolve_raw(cleaned)
        if not raw.get("available"):
            # Never keep unavailable import stubs — they would pollute Library
            # Explorer as "Imported · tap to load" after an invalid Library line.
            self._cache.pop(key, None)
            return None

        full = self._from_resolve(raw, requested_name=cleaned)
        self._cache[key] = full
        # Keep membership name aligned with resolved display name.
        display = full.name
        if display and display not in self._membership_order:
            if key == "builtin":
                self._membership_order.insert(0, display)
            else:
                self._membership_order.append(display)
        elif existing is not None and existing.name != display:
            self._membership_order = [
                display if n.casefold() == key else n for n in self._membership_order
            ]
        return full

    async def get_keyword(
        self,
        *,
        library: str,
        keyword: str,
    ) -> KeywordMetadata | None:
        lib = await self.get_library(library)
        if lib is None:
            return None
        return lib.find_keyword(keyword)

    async def find_keyword(
        self,
        keyword: str,
        *,
        libraries: list[str] | None = None,
    ) -> KeywordMetadata | None:
        """Search libraries (default: membership + BuiltIn) for a keyword."""
        bare = keyword.strip()
        if not bare:
            return None
        libs = list(libraries or [])
        if not libs:
            await self._ensure_membership()
            libs = list(self._membership_order)
        if "BuiltIn" not in libs and not any(n.casefold() == "builtin" for n in libs):
            libs.append("BuiltIn")

        qualifier = ""
        search_names = {bare.casefold()}
        if "." in bare:
            head, _, rest = bare.partition(".")
            if rest:
                qualifier = head.strip()
                search_names.add(rest.casefold())
                libs = [qualifier, *libs]

        for lib_name in libs:
            meta = await self.get_library(lib_name)
            if meta is None:
                continue
            for kw in meta.keywords:
                if kw.name.casefold() in search_names:
                    return kw
                if kw.qualified_name.casefold() == bare.casefold():
                    return kw
        return None

    def _summary_for(self, name: str) -> LibraryMetadata:
        key = name.casefold()
        existing = self._cache.get(key)
        if existing is not None:
            return existing
        builtin = key == "builtin"
        summary = LibraryMetadata(
            name=name,
            source_type=(
                KeywordSourceType.BUILTIN if builtin else KeywordSourceType.LIBRARY
            ),
            builtin=builtin,
            keyword_count=0,
        )
        self._cache[key] = summary
        return summary

    def _ordered_unique_libraries(self) -> list[LibraryMetadata]:
        """Dedupe membership by casefold name (guards concurrent list races)."""
        result: list[LibraryMetadata] = []
        seen: set[str] = set()
        unique_order: list[str] = []
        for name in self._membership_order:
            key = name.casefold()
            if key in seen:
                continue
            seen.add(key)
            unique_order.append(name)
            result.append(self._summary_for(name))
        self._membership_order = unique_order
        return result

    async def _ensure_membership(self, *, extra_imports: list[str] | None = None) -> None:
        if self._membership_ready and not extra_imports:
            return
        self._membership_order = ["BuiltIn"]
        self._summary_for("BuiltIn")
        await self._sync_discovered_imports(extra_imports=extra_imports)
        self._membership_ready = True

    async def _sync_discovered_imports(
        self,
        *,
        extra_imports: list[str] | None = None,
    ) -> None:
        """Resolve discovered imports and append any newly available libraries."""
        seen = {n.casefold() for n in self._membership_order}
        try:
            discovered = await self._discover_imports()
        except Exception:  # noqa: BLE001
            discovered = []
        entries: list[tuple[str, str]] = list(discovered)
        for raw in extra_imports or []:
            name = (raw or "").strip()
            if name:
                entries.append((name, ""))

        for import_name, source_file in entries:
            name = (import_name or "").strip()
            if not name:
                continue
            probe = {name.casefold()}
            stem = Path(name).stem.casefold()
            if stem:
                probe.add(stem)
            if probe & seen:
                continue
            try:
                resolved = await self._resolve_raw(name, file_path=source_file or "")
            except TypeError:
                # Test doubles that only accept ``name``.
                resolved = await self._resolve_raw(name)
            except Exception:  # noqa: BLE001, S112
                continue
            if not resolved.get("available"):
                continue
            full = self._from_resolve(resolved, requested_name=name)
            display = full.name or name
            display_key = display.casefold()
            if display_key in seen:
                # Refresh keywords if we only had a summary stub.
                existing = self._cache.get(display_key)
                if existing is not None and existing.last_updated is None:
                    self._cache[display_key] = full
                continue
            seen.add(display_key)
            self._membership_order.append(display)
            self._cache[display_key] = full
            name_key = name.casefold()
            if name_key != display_key:
                self._cache[name_key] = full
            if stem and stem != display_key:
                self._cache[stem] = full

    @staticmethod
    def _from_resolve(raw: dict[str, Any], *, requested_name: str) -> LibraryMetadata:
        library_name = str(raw.get("name") or requested_name)
        builtin = library_name.casefold() == "builtin"
        source_raw = str(raw.get("source_type") or "").casefold()
        if builtin:
            source_type = KeywordSourceType.BUILTIN
        elif source_raw == KeywordSourceType.REMOTE.value:
            source_type = KeywordSourceType.REMOTE
        else:
            source_type = KeywordSourceType.LIBRARY
        doc_format = str(raw.get("doc_format") or "").upper()
        info_map = raw.get("keyword_info") or {}
        keywords: list[KeywordMetadata] = []
        for kw_name in raw.get("keywords") or []:
            key = str(kw_name).casefold()
            entry = info_map.get(key)
            if isinstance(entry, dict):
                meta = KeywordMetadata.from_transport(entry)
            else:
                meta = KeywordMetadata(
                    name=str(kw_name),
                    qualified_name=f"{library_name}.{kw_name}",
                    source_type=source_type,
                    library_name=library_name,
                )
            if not meta.library_name:
                # ``replace`` so newly added fields are never silently dropped.
                meta = replace(
                    meta,
                    qualified_name=meta.qualified_name or f"{library_name}.{meta.name}",
                    source_type=source_type,
                    library_name=library_name,
                )
            if not meta.doc_format and doc_format:
                meta = replace(meta, doc_format=doc_format)
            keywords.append(meta)

        version = str(raw.get("version") or "")
        documentation = str(raw.get("documentation") or "")
        source_path = ""
        if keywords and keywords[0].source_path:
            source_path = keywords[0].source_path
        source_path = str(raw.get("source") or source_path or "")

        return LibraryMetadata(
            name=library_name,
            version=version,
            documentation=documentation,
            doc_format=doc_format,
            keywords=tuple(keywords),
            source_type=source_type,
            source_path=source_path,
            builtin=builtin,
            keyword_count=len(keywords),
            last_updated=datetime.now(UTC),
        )
