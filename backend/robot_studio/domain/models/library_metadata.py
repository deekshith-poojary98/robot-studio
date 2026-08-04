"""Source-agnostic library metadata — catalog entries for Library Explorer and language features."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from robot_studio.domain.models.keyword_metadata import (
    KeywordMetadata,
    KeywordSourceType,
)


@dataclass(frozen=True)
class LibraryMetadata:
    """A Robot Framework library — independent of how it was discovered.

    Immutable. Cache invalidation / lazy keyword loads replace instances;
    never mutate fields in place. Summaries may have ``keywords=()`` with
    ``keyword_count`` filled after a detail load (new object).
    """

    name: str
    version: str = ""
    documentation: str = ""
    keywords: tuple[KeywordMetadata, ...] = ()
    source_type: KeywordSourceType = KeywordSourceType.LIBRARY
    source_path: str = ""
    builtin: bool = False
    keyword_count: int = 0
    last_updated: datetime | None = None

    def with_keywords(
        self,
        keywords: tuple[KeywordMetadata, ...],
        *,
        version: str | None = None,
        documentation: str | None = None,
        source_path: str | None = None,
    ) -> LibraryMetadata:
        """Return a new instance with populated keywords (lazy-load result)."""
        return LibraryMetadata(
            name=self.name,
            version=version if version is not None else self.version,
            documentation=(
                documentation if documentation is not None else self.documentation
            ),
            keywords=keywords,
            source_type=self.source_type,
            source_path=source_path if source_path is not None else self.source_path,
            builtin=self.builtin,
            keyword_count=len(keywords),
            last_updated=datetime.now(UTC),
        )

    def find_keyword(self, name: str) -> KeywordMetadata | None:
        needle = name.casefold()
        for kw in self.keywords:
            if kw.name.casefold() == needle:
                return kw
            if kw.qualified_name.casefold() == needle:
                return kw
        return None

    def to_summary_api(self) -> dict[str, Any]:
        """REST list payload — no keywords array."""
        return {
            "name": self.name,
            "version": self.version,
            "documentation": self.documentation,
            "source_type": self.source_type.value,
            "source_path": self.source_path,
            "builtin": self.builtin,
            "keyword_count": self.keyword_count,
            "last_updated": self.last_updated.isoformat() if self.last_updated else None,
        }

    def to_api(self) -> dict[str, Any]:
        """REST detail payload including keywords."""
        body = self.to_summary_api()
        body["keywords"] = [kw.to_transport() for kw in self.keywords]
        return body

    @staticmethod
    def from_transport(raw: dict[str, Any]) -> LibraryMetadata:
        source_raw = str(raw.get("source_type") or "library")
        try:
            source_type = KeywordSourceType(source_raw)
        except ValueError:
            source_type = KeywordSourceType.LIBRARY
        keywords_raw = raw.get("keywords") or []
        keywords = tuple(
            KeywordMetadata.from_transport(item)
            for item in keywords_raw
            if isinstance(item, dict)
        )
        count = int(raw.get("keyword_count") or len(keywords) or 0)
        updated = raw.get("last_updated")
        last_updated: datetime | None = None
        if isinstance(updated, datetime):
            last_updated = updated
        elif isinstance(updated, str) and updated:
            try:
                last_updated = datetime.fromisoformat(updated)
            except ValueError:
                last_updated = None
        name = str(raw.get("name") or "")
        builtin = bool(raw.get("builtin")) or name.casefold() == "builtin"
        if builtin:
            source_type = KeywordSourceType.BUILTIN
        return LibraryMetadata(
            name=name,
            version=str(raw.get("version") or ""),
            documentation=str(raw.get("documentation") or ""),
            keywords=keywords,
            source_type=source_type,
            source_path=str(raw.get("source_path") or ""),
            builtin=builtin,
            keyword_count=count if count else len(keywords),
            last_updated=last_updated,
        )
