"""Canonical owner of application preferences.

Sole reader/writer of ``~/.robot-studio/settings.json``. UI, execution, editor,
search, and future features consume this service — never the file directly.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from robot_studio.core.events import EventBus, SettingsUpdated
from robot_studio.domain.models.app_settings import (
    SETTINGS_SCHEMA_VERSION,
    AppSettings,
    migrate_settings_dict,
)

logger = logging.getLogger(__name__)


@dataclass
class SettingsService:
    """Single source of truth for typed application preferences."""

    data_dir: Path
    event_bus: EventBus | None = None
    _current: AppSettings | None = field(default=None, init=False)
    _loaded: bool = field(default=False, init=False)

    @property
    def path(self) -> Path:
        return self.data_dir / "settings.json"

    def load(self) -> AppSettings:
        """Load from disk (or defaults), migrate, and cache."""
        snapshot = self._read_disk()
        self._current = snapshot
        self._loaded = True
        return snapshot

    def get(self) -> AppSettings:
        if not self._loaded or self._current is None:
            return self.load()
        return self._current

    async def update(self, patch: dict[str, Any]) -> AppSettings:
        """Merge *patch* sections, persist, notify observers."""
        current = self.get()
        next_settings = current.merge_patch(patch)
        self._write_disk(next_settings)
        self._current = next_settings
        self._loaded = True
        await self._notify(next_settings)
        return next_settings

    async def replace(self, settings: AppSettings) -> AppSettings:
        """Overwrite with a full snapshot (tests / restore)."""
        normalized = AppSettings.from_api(settings.to_api())
        self._write_disk(normalized)
        self._current = normalized
        self._loaded = True
        await self._notify(normalized)
        return normalized

    async def reset(self) -> AppSettings:
        return await self.replace(AppSettings())

    async def _notify(self, settings: AppSettings) -> None:
        if self.event_bus is None:
            return
        await self.event_bus.publish(SettingsUpdated(version=settings.version))

    def _read_disk(self) -> AppSettings:
        path = self.path
        if not path.is_file():
            defaults = AppSettings()
            try:
                self._write_disk(defaults)
            except OSError as exc:
                logger.warning("Could not create settings.json: %s", exc)
            return defaults
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(raw, dict):
                raw = {}
        except (OSError, json.JSONDecodeError) as exc:
            logger.warning("Corrupt settings.json (%s); using defaults", exc)
            return AppSettings()

        migrated = migrate_settings_dict(raw)
        snapshot = AppSettings.from_api(migrated)
        if int(raw.get("version") or 0) < SETTINGS_SCHEMA_VERSION:
            try:
                self._write_disk(snapshot)
            except OSError as exc:
                logger.warning("Could not rewrite migrated settings: %s", exc)
        return snapshot

    def _write_disk(self, settings: AppSettings) -> None:
        path = self.path
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".json.tmp")
        payload = json.dumps(settings.to_api(), indent=2, sort_keys=True) + "\n"
        tmp.write_text(payload, encoding="utf-8")
        tmp.replace(path)
