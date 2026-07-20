"""Discover and validate plugin manifests."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from pydantic import ValidationError

from robot_studio.domain.models.plugin import PluginManifest


class PluginDiscoveryError(Exception):
    """Raised when plugin discovery fails."""


@dataclass(frozen=True)
class DiscoveredPlugin:
    manifest: PluginManifest
    path: Path


class PluginLoader:
    """Discovers plugins from workspace and user plugin directories."""

    MANIFEST_NAME = "plugin.json"

    def discover(self, *, workspace_path: Path | None = None) -> list[DiscoveredPlugin]:
        discovered: list[DiscoveredPlugin] = []
        seen_ids: set[str] = set()

        for root in self._search_roots(workspace_path):
            if not root.is_dir():
                continue
            for plugin_dir in sorted(root.iterdir()):
                if not plugin_dir.is_dir():
                    continue
                manifest_path = plugin_dir / self.MANIFEST_NAME
                if not manifest_path.is_file():
                    continue
                try:
                    manifest = self.load_manifest(manifest_path)
                except PluginDiscoveryError:
                    continue
                if manifest.id in seen_ids:
                    continue
                seen_ids.add(manifest.id)
                discovered.append(DiscoveredPlugin(manifest=manifest, path=plugin_dir))

        return discovered

    def load_manifest(self, manifest_path: Path) -> PluginManifest:
        try:
            raw = json.loads(manifest_path.read_text(encoding="utf-8"))
        except OSError as exc:
            raise PluginDiscoveryError(
                f"Could not read manifest '{manifest_path}': {exc}",
            ) from exc
        except json.JSONDecodeError as exc:
            raise PluginDiscoveryError(
                f"Invalid JSON in '{manifest_path}': {exc}",
            ) from exc
        try:
            manifest = PluginManifest.model_validate(raw)
        except ValidationError as exc:
            raise PluginDiscoveryError(
                f"Invalid manifest '{manifest_path}': {exc}",
            ) from exc
        entry_path = manifest_path.parent / manifest.entry
        if not entry_path.is_file():
            raise PluginDiscoveryError(
                f"Entry point '{manifest.entry}' not found for plugin '{manifest.id}'",
            )
        return manifest

    def _search_roots(self, workspace_path: Path | None) -> list[Path]:
        roots: list[Path] = []
        if workspace_path is not None:
            roots.append(workspace_path / "Plugins")
        roots.append(Path.home() / ".robotstudio" / "plugins")
        return roots
