"""Application facade for plugin management."""

from __future__ import annotations

from dataclasses import dataclass

from robot_studio.domain.models.plugin import PluginInfo
from robot_studio.infrastructure.plugins.plugin_manager import (
    PluginManager,
    PluginManagerError,
)


class PluginValidationError(Exception):
    """Raised when a plugin request cannot be satisfied."""


@dataclass
class PluginService:
    manager: PluginManager

    async def list_plugins(self) -> list[PluginInfo]:
        return self.manager.list_plugins()

    async def get_plugin(self, plugin_id: str) -> PluginInfo | None:
        return self.manager.get_plugin(plugin_id)

    async def enable_plugin(self, plugin_id: str) -> PluginInfo:
        try:
            return await self.manager.enable(plugin_id)
        except PluginManagerError as exc:
            raise PluginValidationError(str(exc)) from exc

    async def disable_plugin(self, plugin_id: str) -> PluginInfo:
        try:
            return await self.manager.disable(plugin_id)
        except PluginManagerError as exc:
            raise PluginValidationError(str(exc)) from exc

    async def reload_plugin(self, plugin_id: str) -> PluginInfo:
        try:
            return await self.manager.reload(plugin_id)
        except PluginManagerError as exc:
            raise PluginValidationError(str(exc)) from exc

    async def refresh(self) -> list[PluginInfo]:
        await self.manager.discover_and_load()
        return self.manager.list_plugins()
