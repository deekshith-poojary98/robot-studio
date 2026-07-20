"""Load external plugin entry points."""

from __future__ import annotations

import importlib.util
import inspect
import sys
from pathlib import Path
from typing import Any, Protocol, runtime_checkable


class PluginLoadError(Exception):
    """Raised when a plugin entry point cannot be loaded."""


@runtime_checkable
class RobotStudioPlugin(Protocol):
    async def initialize(self, context: Any) -> None: ...

    async def activate(self, context: Any) -> None: ...

    async def deactivate(self, context: Any) -> None: ...

    async def dispose(self, context: Any) -> None: ...


class NoOpPlugin:
    """Fallback plugin implementation for manifests without a Python class."""

    async def initialize(self, context: Any) -> None:
        return None

    async def activate(self, context: Any) -> None:
        return None

    async def deactivate(self, context: Any) -> None:
        return None

    async def dispose(self, context: Any) -> None:
        return None


def load_plugin_module(plugin_dir: Path, entry: str) -> Any:
    entry_path = plugin_dir / entry
    if not entry_path.is_file():
        raise PluginLoadError(f"Entry point not found: {entry_path}")

    module_name = f"robot_studio_plugin_{plugin_dir.name}"
    spec = importlib.util.spec_from_file_location(module_name, entry_path)
    if spec is None or spec.loader is None:
        raise PluginLoadError(f"Could not load plugin module from {entry_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except Exception as exc:  # noqa: BLE001 — plugin boundary
        raise PluginLoadError(f"Plugin module failed to execute: {exc}") from exc

    if hasattr(module, "create_plugin") and callable(module.create_plugin):
        return module.create_plugin()

    plugin_cls = getattr(module, "Plugin", None)
    if plugin_cls is not None and inspect.isclass(plugin_cls):
        return plugin_cls()

    return NoOpPlugin()
