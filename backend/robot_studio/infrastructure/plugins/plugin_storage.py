"""Per-plugin key-value storage."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class PluginStorage:
    """Isolated JSON storage for a single plugin."""

    def __init__(self, root: Path, plugin_id: str) -> None:
        self._path = root / f"{plugin_id}.json"
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._cache: dict[str, Any] | None = None

    def _load(self) -> dict[str, Any]:
        if self._cache is not None:
            return self._cache
        if not self._path.is_file():
            self._cache = {}
            return self._cache
        try:
            self._cache = json.loads(self._path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            self._cache = {}
        return self._cache

    def _save(self) -> None:
        data = self._load()
        self._path.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def get(self, key: str, default: Any = None) -> Any:
        return self._load().get(key, default)

    def set(self, key: str, value: Any) -> None:
        data = self._load()
        data[key] = value
        self._save()

    def delete(self, key: str) -> None:
        data = self._load()
        if key in data:
            del data[key]
            self._save()

    def clear(self) -> None:
        self._cache = {}
        if self._path.is_file():
            self._path.unlink()

    def all(self) -> dict[str, Any]:
        return dict(self._load())
