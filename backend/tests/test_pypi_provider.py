"""Tests for PyPI search via the cached Simple API name index."""

from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest
from robot_studio.infrastructure.packages.pypi_provider import PyPIProvider


def _simple_payload(names: list[str]) -> dict:
    return {"projects": [{"name": name} for name in names]}


def _project_payload(name: str, version: str = "1.0.0", summary: str = "desc") -> dict:
    return {
        "info": {
            "name": name,
            "version": version,
            "summary": summary,
            "author": "Tester",
            "home_page": "https://example.com",
            "license": "MIT",
            "requires_dist": [],
        },
        "releases": {version: [{"packagetype": "sdist"}]},
    }


@pytest.fixture
def provider(tmp_path: Path) -> PyPIProvider:
    names = [
        "unrelated",
        "filewatcher",
        "libfilewatcher",
        "robotframework-filewatcher",
        "EasyFileWatcher",
        "pytest-file-watcher",
        "watchdog",
        "robotframework",
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path.rstrip("/")
        if path == "/simple" or path == "/simple/":
            return httpx.Response(200, json=_simple_payload(names))
        if path.startswith("/pypi/") and path.endswith("/json"):
            pkg = path.removeprefix("/pypi/").removesuffix("/json")
            if pkg.lower() == "missing":
                return httpx.Response(404)
            # Preserve canonical casing from the index when possible.
            canonical = next(
                (name for name in names if name.lower() == pkg.lower()),
                pkg,
            )
            return httpx.Response(
                200,
                json=_project_payload(canonical, summary=f"Summary for {canonical}"),
            )
        return httpx.Response(404)

    client = httpx.AsyncClient(
        base_url="https://pypi.org",
        transport=httpx.MockTransport(handler),
    )
    return PyPIProvider(client=client, cache_dir=tmp_path / "cache", max_search_results=20)


@pytest.mark.asyncio
async def test_search_returns_ranked_top_matches(provider: PyPIProvider) -> None:
    results = await provider.search("filewatcher")
    names = [item["name"] for item in results]
    assert names[0] == "filewatcher"
    assert "libfilewatcher" in names
    assert "robotframework-filewatcher" in names
    assert "EasyFileWatcher" in names
    assert "pytest-file-watcher" in names
    assert "watchdog" not in names
    assert "unrelated" not in names
    assert len(names) <= 20
    assert all(item.get("latest_version") for item in results)


@pytest.mark.asyncio
async def test_search_caps_at_twenty(tmp_path: Path) -> None:
    names = [f"robot-{i:03d}" for i in range(40)]
    names.insert(0, "robot")

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path.rstrip("/")
        if path.endswith("/simple"):
            return httpx.Response(200, json=_simple_payload(names))
        pkg = path.removeprefix("/pypi/").removesuffix("/json")
        return httpx.Response(200, json=_project_payload(pkg))

    client = httpx.AsyncClient(
        base_url="https://pypi.org",
        transport=httpx.MockTransport(handler),
    )
    provider = PyPIProvider(
        client=client,
        cache_dir=tmp_path / "cache",
        max_search_results=20,
    )
    results = await provider.search("robot")
    assert len(results) == 20
    assert results[0]["name"] == "robot"


@pytest.mark.asyncio
async def test_name_index_is_cached_on_disk(provider: PyPIProvider, tmp_path: Path) -> None:
    await provider.search("filewatcher")
    cache = tmp_path / "cache" / "pypi-package-names.json"
    assert cache.is_file()
    payload = json.loads(cache.read_text(encoding="utf-8"))
    assert "filewatcher" in payload["names"]
    assert payload["fetched_at"] > 0


@pytest.mark.asyncio
async def test_search_uses_disk_cache_when_simple_index_fails(tmp_path: Path) -> None:
    cache_dir = tmp_path / "cache"
    cache_dir.mkdir(parents=True)
    (cache_dir / "pypi-package-names.json").write_text(
        json.dumps(
            {
                "fetched_at": 0,  # expired
                "names": ["filewatcher", "libfilewatcher", "other"],
            },
        ),
        encoding="utf-8",
    )

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path.rstrip("/")
        if path.endswith("/simple"):
            return httpx.Response(503)
        pkg = path.removeprefix("/pypi/").removesuffix("/json")
        return httpx.Response(200, json=_project_payload(pkg))

    client = httpx.AsyncClient(
        base_url="https://pypi.org",
        transport=httpx.MockTransport(handler),
    )
    provider = PyPIProvider(client=client, cache_dir=cache_dir)
    results = await provider.search("filewatcher")
    assert [item["name"] for item in results] == ["filewatcher", "libfilewatcher"]
