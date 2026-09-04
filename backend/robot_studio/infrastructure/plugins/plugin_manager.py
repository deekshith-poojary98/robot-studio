"""Plugin lifecycle orchestration."""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from robot_studio.application.services.environment_service import EnvironmentService
from robot_studio.application.services.execution_service import ExecutionService
from robot_studio.application.services.language_service import LanguageFacade
from robot_studio.application.services.project_service import ProjectService
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.config import Settings
from robot_studio.core.events import (
    EventBus,
    PluginDisabled,
    PluginEnabled,
    PluginFailed,
    PluginLoaded,
    PluginReloaded,
    WorkspaceOpened,
)
from robot_studio.core.plugins import PluginHost
from robot_studio.domain.interfaces.plugins import Capability
from robot_studio.domain.models.plugin import PluginInfo, PluginManifest, utc_now
from robot_studio.infrastructure.plugins.builtin_plugins import (
    BUILTIN_PLUGIN_SPECS,
    BuiltinPluginAdapter,
)
from robot_studio.infrastructure.plugins.plugin_context import PluginContext
from robot_studio.infrastructure.plugins.plugin_loader import (
    DiscoveredPlugin,
    PluginLoader,
)
from robot_studio.infrastructure.plugins.plugin_runtime import (
    PluginLoadError,
    load_plugin_module,
)
from robot_studio.infrastructure.plugins.plugin_storage import PluginStorage

logger = logging.getLogger(__name__)


class PluginManagerError(Exception):
    """Raised when plugin operations fail."""


@dataclass
class LoadedPlugin:
    manifest: PluginManifest
    path: Path | None
    instance: Any
    is_builtin: bool
    status: str = "loaded"
    enabled: bool = True
    error: str | None = None
    loaded_at: datetime | None = None


@dataclass
class PluginManager:
    plugin_host: PluginHost
    event_bus: EventBus
    workspace_context: WorkspaceContext
    settings: Settings
    project_service: ProjectService
    environment_service: EnvironmentService
    execution_service: ExecutionService
    language_facade: LanguageFacade
    storage_root: Path
    loader: PluginLoader = field(default_factory=PluginLoader)
    _plugins: dict[str, LoadedPlugin] = field(default_factory=dict)
    _state_path: Path | None = None
    _subscribed: bool = field(default=False, init=False)

    def configure_state_path(self, path: Path) -> None:
        self._state_path = path
        self._state_path.parent.mkdir(parents=True, exist_ok=True)

    async def initialize(self) -> None:
        if not self._subscribed:
            self.event_bus.subscribe(WorkspaceOpened, self._on_workspace_opened)
            self._subscribed = True
        await self.load_builtins()
        await self.discover_and_load()

    async def _on_workspace_opened(self, event: WorkspaceOpened) -> None:
        _ = event
        await self.discover_and_load()

    async def load_builtins(self) -> None:
        enabled_state = self._read_state()
        for spec in BUILTIN_PLUGIN_SPECS:
            plugin_id = spec.manifest.id
            enabled = enabled_state.get(plugin_id, True)
            record = LoadedPlugin(
                manifest=spec.manifest,
                path=None,
                instance=BuiltinPluginAdapter(spec),
                is_builtin=True,
                status="enabled" if enabled else "disabled",
                enabled=enabled,
                loaded_at=utc_now(),
            )
            self._plugins[plugin_id] = record
            await self.event_bus.publish(PluginLoaded(plugin_id=plugin_id))
            if enabled:
                await self.event_bus.publish(PluginEnabled(plugin_id=plugin_id))

    async def discover_and_load(self) -> None:
        workspace_path = (
            self.workspace_context.workspace.path
            if self.workspace_context.workspace is not None
            else None
        )
        try:
            discovered = self.loader.discover(workspace_path=workspace_path)
        except Exception as exc:  # noqa: BLE001 — discovery boundary
            logger.warning("Plugin discovery failed: %s", exc)
            return

        enabled_state = self._read_state()
        for item in discovered:
            if item.manifest.id in self._plugins:
                continue
            await self._load_discovered(item, enabled=enabled_state.get(item.manifest.id, True))

    async def _load_discovered(self, item: DiscoveredPlugin, *, enabled: bool) -> None:
        plugin_id = item.manifest.id
        try:
            instance = load_plugin_module(item.path, item.manifest.entry)
        except PluginLoadError as exc:
            record = LoadedPlugin(
                manifest=item.manifest,
                path=item.path,
                instance=None,
                is_builtin=False,
                status="failed",
                enabled=False,
                error=str(exc),
            )
            self._plugins[plugin_id] = record
            await self.event_bus.publish(
                PluginFailed(plugin_id=plugin_id, message=str(exc)),
            )
            return

        record = LoadedPlugin(
            manifest=item.manifest,
            path=item.path,
            instance=instance,
            is_builtin=False,
            status="loaded",
            enabled=enabled,
            loaded_at=utc_now(),
        )
        self._plugins[plugin_id] = record
        context = self._build_context(plugin_id)
        try:
            await instance.initialize(context)
            await self.event_bus.publish(PluginLoaded(plugin_id=plugin_id))
            if enabled:
                await self._activate_record(record, context)
            else:
                record.status = "disabled"
        except Exception as exc:  # noqa: BLE001 — plugin boundary
            record.status = "failed"
            record.enabled = False
            record.error = str(exc)
            await self.event_bus.publish(
                PluginFailed(plugin_id=plugin_id, message=str(exc)),
            )

    async def enable(self, plugin_id: str) -> PluginInfo:
        record = self._require_record(plugin_id)
        if record.enabled and record.status == "enabled":
            return self.to_info(record)
        context = self._build_context(plugin_id)
        try:
            if record.instance is None:
                raise PluginManagerError("Plugin instance is unavailable")
            if record.status == "loaded":
                await record.instance.initialize(context)
            await self._activate_record(record, context)
            self._write_state(plugin_id, True)
        except Exception as exc:
            record.status = "failed"
            record.enabled = False
            record.error = str(exc)
            await self.event_bus.publish(
                PluginFailed(plugin_id=plugin_id, message=str(exc)),
            )
            raise PluginManagerError(str(exc)) from exc
        return self.to_info(record)

    async def disable(self, plugin_id: str) -> PluginInfo:
        record = self._require_record(plugin_id)
        if record.is_builtin:
            raise PluginManagerError("Built-in plugins cannot be disabled")
        if not record.enabled:
            return self.to_info(record)
        context = self._build_context(plugin_id)
        try:
            if record.instance is not None:
                await record.instance.deactivate(context)
            self.plugin_host.unregister_plugin(plugin_id)
            record.enabled = False
            record.status = "disabled"
            self._write_state(plugin_id, False)
            await self.event_bus.publish(PluginDisabled(plugin_id=plugin_id))
        except Exception as exc:
            record.error = str(exc)
            raise PluginManagerError(str(exc)) from exc
        return self.to_info(record)

    async def reload(self, plugin_id: str) -> PluginInfo:
        record = self._require_record(plugin_id)
        if record.is_builtin:
            await self.event_bus.publish(PluginReloaded(plugin_id=plugin_id))
            return self.to_info(record)
        if record.path is None:
            raise PluginManagerError("Plugin path is unavailable")

        was_enabled = record.enabled
        if record.enabled and record.instance is not None:
            context = self._build_context(plugin_id)
            await record.instance.deactivate(context)
            await record.instance.dispose(context)
        self.plugin_host.unregister_plugin(plugin_id)
        self._plugins.pop(plugin_id, None)
        await self._load_discovered(
            DiscoveredPlugin(manifest=record.manifest, path=record.path),
            enabled=was_enabled,
        )
        await self.event_bus.publish(PluginReloaded(plugin_id=plugin_id))
        return self.to_info(self._require_record(plugin_id))

    def list_plugins(self) -> list[PluginInfo]:
        return [self.to_info(record) for record in self._plugins.values()]

    def get_plugin(self, plugin_id: str) -> PluginInfo | None:
        record = self._plugins.get(plugin_id)
        if record is None:
            return None
        return self.to_info(record)

    def to_info(self, record: LoadedPlugin) -> PluginInfo:
        return PluginInfo.from_record(
            record.manifest,
            status=record.status,
            enabled=record.enabled,
            path=str(record.path) if record.path else None,
            is_builtin=record.is_builtin,
            error=record.error,
            loaded_at=record.loaded_at,
        )

    async def _activate_record(self, record: LoadedPlugin, context: PluginContext) -> None:
        if record.instance is None:
            raise PluginManagerError("Plugin instance is unavailable")
        await record.instance.activate(context)
        self._register_capabilities(record)
        record.enabled = True
        record.status = "enabled"
        record.error = None
        await self.event_bus.publish(PluginEnabled(plugin_id=record.manifest.id))

    def _register_capabilities(self, record: LoadedPlugin) -> None:
        plugin_id = record.manifest.id
        from robot_studio.domain.interfaces.plugins import capability_from_manifest

        for capability_name in record.manifest.capabilities:
            capability = capability_from_manifest(capability_name)
            if capability is None:
                continue
            if capability in {
                Capability.TOOLBAR_ACTION,
                Capability.SIDEBAR_PANEL,
                Capability.CONTEXT_MENU,
                Capability.SETTINGS_PAGE,
                Capability.EXPLORER_NODE_PROVIDER,
            }:
                self.plugin_host.register_extension(
                    capability,
                    provider_id=plugin_id,
                    plugin_id=plugin_id,
                    metadata={"name": record.manifest.name},
                )

    def _build_context(self, plugin_id: str) -> PluginContext:
        return PluginContext(
            plugin_id=plugin_id,
            workspace_context=self.workspace_context,
            event_bus=self.event_bus,
            storage=PluginStorage(self.storage_root, plugin_id),
            logger=logging.getLogger(f"robot_studio.plugin.{plugin_id}"),
            settings=self.settings,
            project_service=self.project_service,
            environment_service=self.environment_service,
            execution_service=self.execution_service,
            language_facade=self.language_facade,
        )

    def _require_record(self, plugin_id: str) -> LoadedPlugin:
        record = self._plugins.get(plugin_id)
        if record is None:
            raise PluginManagerError(f"Plugin '{plugin_id}' was not found")
        return record

    def _read_state(self) -> dict[str, bool]:
        if self._state_path is None or not self._state_path.is_file():
            return {}
        try:
            data = json.loads(self._state_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}
        return {str(key): bool(value) for key, value in data.items()}

    def _write_state(self, plugin_id: str, enabled: bool) -> None:
        if self._state_path is None:
            return
        state = self._read_state()
        state[plugin_id] = enabled
        self._state_path.write_text(json.dumps(state, indent=2), encoding="utf-8")
