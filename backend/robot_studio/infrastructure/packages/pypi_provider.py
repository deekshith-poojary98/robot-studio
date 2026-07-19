"""PyPI package registry — PackageRegistry capability implementation."""

from __future__ import annotations

import re
from urllib.parse import quote

import httpx

from robot_studio.domain.interfaces.installer import PackageRegistry

_NAME_RE = re.compile(
    r'class="package-snippet__name"[^>]*>\s*([^<]+)\s*<',
    re.IGNORECASE,
)
_VERSION_RE = re.compile(
    r'class="package-snippet__version"[^>]*>\s*([^<]+)\s*<',
    re.IGNORECASE,
)
_DESC_RE = re.compile(
    r'class="package-snippet__description"[^>]*>\s*([^<]*)\s*<',
    re.IGNORECASE,
)
_SNIPPET_RE = re.compile(
    r'class="package-snippet"[^>]*>(.*?)</a>',
    re.IGNORECASE | re.DOTALL,
)


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
    """Fetches package metadata and search results from pypi.org."""

    def __init__(
        self,
        *,
        base_url: str = "https://pypi.org",
        client: httpx.AsyncClient | None = None,
        timeout: float = 20.0,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._client = client
        self._timeout = timeout
        self._owns_client = client is None

    async def aclose(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    async def search(self, query: str) -> list[dict]:
        cleaned = query.strip()
        if not cleaned:
            return []

        results: list[dict] = []
        exact = await self.get_metadata(cleaned)
        if exact is not None:
            results.append(exact)

        html = await self._get_text(f"/search/?q={quote(cleaned)}&o=")
        for snippet in _SNIPPET_RE.findall(html or ""):
            name_match = _NAME_RE.search(snippet)
            if not name_match:
                continue
            name = name_match.group(1).strip()
            if any(item["name"].lower() == name.lower() for item in results):
                continue
            version_match = _VERSION_RE.search(snippet)
            desc_match = _DESC_RE.search(snippet)
            results.append(
                {
                    "name": name,
                    "latest_version": (
                        version_match.group(1).strip() if version_match else ""
                    ),
                    "summary": (
                        desc_match.group(1).strip() if desc_match else None
                    ),
                },
            )
            if len(results) >= 25:
                break

        # Fill missing versions via JSON API for precision when HTML omitted them.
        filled: list[dict] = []
        for item in results:
            if item.get("latest_version"):
                filled.append(item)
                continue
            meta = await self.get_metadata(item["name"])
            if meta is not None:
                filled.append(meta)
            else:
                filled.append(item)
        return filled

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

    async def _get_text(self, path: str) -> str | None:
        client = await self._client_or_create()
        try:
            response = await client.get(path)
        except httpx.HTTPError:
            return None
        if response.status_code >= 400:
            return None
        return response.text
