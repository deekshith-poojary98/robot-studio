"""PyPI package registry — PackageRegistry capability implementation."""

from __future__ import annotations

import asyncio
import json
import logging
import re
import time
from pathlib import Path
from urllib.parse import quote

import httpx

from robot_studio.domain.interfaces.installer import PackageRegistry
from robot_studio.infrastructure.packages.package_match import rank_packages

logger = logging.getLogger(__name__)

# Search UI shows a compact list; hydrate at most this many after ranking.
_MAX_SEARCH_RESULTS = 20
# Refresh the local name index at most once per day.
_NAME_INDEX_TTL_SECONDS = 24 * 60 * 60
_NAME_INDEX_FILENAME = "pypi-package-names.json"


def _version_sort_key(version: str) -> tuple:
    """Best-effort PEP-ish sort without depending on packaging."""
    parts: list[object] = []
    for chunk in re.split(r"[.+_-]", version):
        if chunk.isdigit():
            parts.append((0, int(chunk)))
        else:
            parts.append((1, chunk.lower()))
    return tuple(parts)


class PyPIProvider(PackageRegistry):
    """Fetches package metadata and search results from pypi.org.

    Warehouse's HTML ``/search`` is behind a bot challenge, so discovery uses
    the public Simple API name index (cached under ``cache_dir``) plus the
    JSON project API for versions/summaries. Results are ranked
    exact → prefix → substring → fuzzy and capped at 20.
    """

    def __init__(
        self,
        *,
        base_url: str = "https://pypi.org",
        client: httpx.AsyncClient | None = None,
        timeout: float = 20.0,
        cache_dir: Path | None = None,
        name_index_ttl_seconds: int = _NAME_INDEX_TTL_SECONDS,
        max_search_results: int = _MAX_SEARCH_RESULTS,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._client = client
        self._timeout = timeout
        self._owns_client = client is None
        self._cache_dir = (
            Path(cache_dir).expanduser()
            if cache_dir is not None
            else Path.home() / ".robot-studio" / "cache"
        )
        self._name_index_ttl_seconds = max(60, int(name_index_ttl_seconds))
        self._max_search_results = max(1, int(max_search_results))
        self._names_memory: list[str] | None = None
        self._names_fetched_at: float | None = None
        self._names_lock = asyncio.Lock()

    async def aclose(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    async def search(self, query: str) -> list[dict]:
        cleaned = query.strip()
        if not cleaned:
            return []

        names = await self._package_names()
        ranked_names = [
            item["name"]
            for item in rank_packages(
                [{"name": name, "summary": None} for name in names],
                cleaned,
            )
        ][: self._max_search_results]

        # Exact JSON lookup always wins a slot even if the index is stale.
        exact = await self.get_metadata(cleaned)
        ordered: list[str] = []
        if exact is not None:
            ordered.append(str(exact["name"]))
        for name in ranked_names:
            if all(name.lower() != existing.lower() for existing in ordered):
                ordered.append(name)
            if len(ordered) >= self._max_search_results:
                break

        if not ordered and exact is None:
            # Brand-new index miss — still try the typed name.
            return []

        hydrated = await self._hydrate_many(ordered)
        # Preserve rank order; drop empties.
        by_lower = {str(item["name"]).lower(): item for item in hydrated}
        results: list[dict] = []
        for name in ordered:
            item = by_lower.get(name.lower())
            if item is not None:
                results.append(item)
            elif exact is not None and name.lower() == str(exact["name"]).lower():
                results.append(exact)
            else:
                results.append(
                    {
                        "name": name,
                        "latest_version": "",
                        "summary": None,
                    },
                )
        return results[: self._max_search_results]

    async def get_latest_version(self, name: str) -> str | None:
        meta = await self.get_metadata(name)
        if meta is None:
            return None
        version = meta.get("latest_version")
        return str(version) if version else None

    async def get_metadata(self, name: str) -> dict | None:
        cleaned = name.strip()
        if not cleaned:
            return None
        payload = await self._get_json(f"/pypi/{quote(cleaned)}/json")
        if payload is None:
            return None
        info = payload.get("info") or {}
        return {
            "name": str(info.get("name") or cleaned),
            "latest_version": str(info.get("version") or ""),
            "summary": info.get("summary") or None,
            "author": info.get("author") or info.get("author_email") or None,
            "homepage": info.get("home_page") or info.get("project_url") or None,
            "license": info.get("license") or None,
            "requires": list(info.get("requires_dist") or []),
        }

    async def list_versions(self, name: str) -> list[str]:
        """Return available release versions, newest-first, latest first."""
        cleaned = name.strip()
        if not cleaned:
            return []
        payload = await self._get_json(f"/pypi/{quote(cleaned)}/json")
        if payload is None:
            return []
        info = payload.get("info") or {}
        latest = str(info.get("version") or "").strip()
        releases = payload.get("releases") or {}
        if not isinstance(releases, dict):
            return [latest] if latest else []

        versions = [
            str(version)
            for version, files in releases.items()
            if version and isinstance(files, list) and files
        ]
        if not versions and latest:
            return [latest]

        versions.sort(key=_version_sort_key, reverse=True)
        if latest:
            if latest in versions:
                versions.remove(latest)
            versions.insert(0, latest)
        return versions

    async def _hydrate_many(self, names: list[str]) -> list[dict]:
        if not names:
            return []
        semaphore = asyncio.Semaphore(8)

        async def one(name: str) -> dict | None:
            async with semaphore:
                return await self.get_metadata(name)

        return [item for item in await asyncio.gather(*(one(n) for n in names)) if item]

    async def _package_names(self) -> list[str]:
        async with self._names_lock:
            now = time.time()
            if (
                self._names_memory is not None
                and self._names_fetched_at is not None
                and now - self._names_fetched_at < self._name_index_ttl_seconds
            ):
                return self._names_memory

            cached = self._read_name_cache(now)
            if cached is not None:
                self._names_memory = cached
                self._names_fetched_at = now
                return cached

            fetched = await self._fetch_simple_names()
            if fetched:
                self._write_name_cache(fetched, now)
                self._names_memory = fetched
                self._names_fetched_at = now
                return fetched

            # Network failed — fall back to a stale cache if we have one.
            stale = self._read_name_cache(now, ignore_ttl=True)
            if stale is not None:
                logger.warning("Using stale PyPI name index; live refresh failed")
                self._names_memory = stale
                self._names_fetched_at = now
                return stale
            return self._names_memory or []

    def _cache_path(self) -> Path:
        return self._cache_dir / _NAME_INDEX_FILENAME

    def _read_name_cache(
        self,
        now: float,
        *,
        ignore_ttl: bool = False,
    ) -> list[str] | None:
        path = self._cache_path()
        if not path.is_file():
            return None
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            return None
        if not isinstance(payload, dict):
            return None
        fetched_at = float(payload.get("fetched_at") or 0)
        names = payload.get("names")
        if not isinstance(names, list) or not names:
            return None
        if not ignore_ttl and now - fetched_at > self._name_index_ttl_seconds:
            return None
        cleaned = [str(name) for name in names if str(name).strip()]
        return cleaned or None

    def _write_name_cache(self, names: list[str], fetched_at: float) -> None:
        path = self._cache_path()
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                json.dumps({"fetched_at": fetched_at, "names": names}),
                encoding="utf-8",
            )
        except OSError as exc:
            logger.debug("Could not write PyPI name cache: %s", exc)

    async def _fetch_simple_names(self) -> list[str]:
        client = await self._client_or_create()
        try:
            response = await client.get(
                "/simple/",
                headers={"Accept": "application/vnd.pypi.simple.v1+json"},
            )
        except httpx.HTTPError as exc:
            logger.warning("PyPI simple index fetch failed: %s", exc)
            return []
        if response.status_code >= 400:
            logger.warning(
                "PyPI simple index HTTP %s",
                response.status_code,
            )
            return []
        try:
            payload = response.json()
        except ValueError:
            return []
        projects = payload.get("projects") if isinstance(payload, dict) else None
        if not isinstance(projects, list):
            return []
        names: list[str] = []
        for item in projects:
            if isinstance(item, dict):
                name = str(item.get("name") or "").strip()
            else:
                name = str(item).strip()
            if name:
                names.append(name)
        return names

    async def _client_or_create(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                base_url=self._base_url,
                timeout=self._timeout,
                headers={"User-Agent": "RobotStudio/0.1 (PackageManager)"},
                follow_redirects=True,
            )
        return self._client

    async def _get_json(self, path: str) -> dict | None:
        client = await self._client_or_create()
        try:
            response = await client.get(path)
        except httpx.HTTPError:
            return None
        if response.status_code == 404:
            return None
        if response.status_code >= 400:
            return None
        try:
            data = response.json()
        except ValueError:
            return None
        return data if isinstance(data, dict) else None
