"""Backend tests for LibraryCatalogService and library API shapes."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from robot_studio.domain.models.keyword_metadata import (
    KeywordMetadata,
    KeywordSourceType,
    ParameterMetadata,
)
from robot_studio.domain.models.library_metadata import LibraryMetadata
from robot_studio.infrastructure.language.library_catalog import LibraryCatalogService


@pytest.mark.asyncio
async def test_catalog_list_is_summary_only_and_stable_identity() -> None:
    resolve_calls: list[str] = []

    async def resolve_raw(name: str) -> dict:
        resolve_calls.append(name)
        return {
            "available": True,
            "name": name,
            "keywords": ["Alpha", "Beta"],
            "keyword_info": {
                "alpha": {
                    "name": "Alpha",
                    "documentation": "A",
                    "parameters": [{"name": "x", "label": "x", "required": True}],
                    "source_type": "library",
                    "library_name": name,
                },
                "beta": {
                    "name": "Beta",
                    "documentation": "B",
                    "parameters": [],
                    "source_type": "library",
                    "library_name": name,
                },
            },
        }

    async def discover() -> list[str]:
        return ["Collections"]

    catalog = LibraryCatalogService(
        _resolve_raw=resolve_raw,
        _discover_imports=discover,
    )
    summaries = await catalog.list_libraries()
    assert resolve_calls == []
    assert any(lib.name == "BuiltIn" for lib in summaries)
    assert any(lib.name == "Collections" for lib in summaries)
    collections = next(lib for lib in summaries if lib.name == "Collections")
    assert collections.keywords == ()
    assert collections.keyword_count == 0

    again = await catalog.list_libraries()
    assert again[0] is summaries[0]
    collections2 = next(lib for lib in again if lib.name == "Collections")
    assert collections2 is collections

    detail = await catalog.get_library("Collections")
    assert detail is not None
    assert resolve_calls == ["Collections"]
    assert len(detail.keywords) == 2
    assert detail.keyword_count == 2
    assert detail.last_updated is not None

    detail2 = await catalog.get_library("Collections")
    assert detail2 is detail
    assert resolve_calls == ["Collections"]


@pytest.mark.asyncio
async def test_catalog_invalidate_replaces_instances() -> None:
    async def resolve_raw(name: str) -> dict:
        return {
            "available": True,
            "name": "BuiltIn",
            "keywords": ["Log"],
            "keyword_info": {
                "log": {
                    "name": "Log",
                    "parameters": [],
                    "source_type": "builtin",
                    "library_name": "BuiltIn",
                },
            },
        }

    async def discover() -> list[str]:
        return []

    catalog = LibraryCatalogService(
        _resolve_raw=resolve_raw,
        _discover_imports=discover,
    )
    first = await catalog.get_library("BuiltIn")
    catalog.invalidate()
    second = await catalog.get_library("BuiltIn")
    assert first is not None and second is not None
    assert first is not second


def test_library_metadata_immutable_with_keywords() -> None:
    summary = LibraryMetadata(name="X", builtin=False, keyword_count=0)
    full = summary.with_keywords(
        (
            KeywordMetadata(
                name="K",
                source_type=KeywordSourceType.LIBRARY,
                library_name="X",
                parameters=(ParameterMetadata(name="a", required=True),),
            ),
        ),
    )
    assert summary.keywords == ()
    assert full.keyword_count == 1
    assert full.last_updated is not None
    assert full.last_updated.tzinfo == UTC or full.last_updated.tzinfo is not None
    api = full.to_summary_api()
    assert "keywords" not in api
    detail = full.to_api()
    assert len(detail["keywords"]) == 1
