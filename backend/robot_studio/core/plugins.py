"""Plugin host extensions and plugin-scoped capability tracking."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any, TypeVar

from robot_studio.domain.interfaces.plugins import Capability

T = TypeVar("T")

CapabilityFactory = Callable[[], Any]

# Module names exposed via the health endpoint (API-stable list).
REGISTERED_MODULES: list[str] = [
    "workspace",
    "project",
    "environment",
    "packages",
    "libraries",
    "keywords",
    "execution",
    "reports",
    "settings",
]


@dataclass
class CapabilityRegistration:
    capability: Capability
    provider_id: str
    factory: CapabilityFactory | None = None
    plugin_id: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class PluginHost:
    """Registry for built-in and plugin capability providers."""

    _registrations: dict[Capability, CapabilityRegistration] = field(
        default_factory=dict,
    )
    _plugin_registrations: dict[str, list[CapabilityRegistration]] = field(
        default_factory=dict,
    )
    _extensions: dict[Capability, list[CapabilityRegistration]] = field(
        default_factory=dict,
    )

    def register(
        self,
        capability: Capability,
        provider_id: str,
        factory: CapabilityFactory | None = None,
        *,
        plugin_id: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        registration = CapabilityRegistration(
            capability=capability,
            provider_id=provider_id,
            factory=factory,
            plugin_id=plugin_id,
            metadata=metadata or {},
        )
        self._registrations[capability] = registration
        if plugin_id:
            self._plugin_registrations.setdefault(plugin_id, []).append(registration)

    def register_extension(
        self,
        capability: Capability,
        provider_id: str,
        *,
        plugin_id: str,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        registration = CapabilityRegistration(
            capability=capability,
            provider_id=provider_id,
            factory=None,
            plugin_id=plugin_id,
            metadata=metadata or {},
        )
        self._extensions.setdefault(capability, []).append(registration)
        self._plugin_registrations.setdefault(plugin_id, []).append(registration)

    def unregister_plugin(self, plugin_id: str) -> None:
        registrations = self._plugin_registrations.pop(plugin_id, [])
        for registration in registrations:
            current = self._registrations.get(registration.capability)
            if current is not None and current.plugin_id == plugin_id:
                self._registrations.pop(registration.capability, None)
            extension_list = self._extensions.get(registration.capability, [])
            self._extensions[registration.capability] = [
                item for item in extension_list if item.plugin_id != plugin_id
            ]

    def get(self, capability: Capability) -> Any:
        registration = self._registrations.get(capability)
        if registration is None:
            raise KeyError(f"No provider registered for capability: {capability.value}")
        if registration.factory is None:
            raise RuntimeError(
                f"Capability '{capability.value}' is registered "
                f"({registration.provider_id}) but has no factory yet",
            )
        return registration.factory()

    def has(self, capability: Capability) -> bool:
        registration = self._registrations.get(capability)
        return registration is not None and registration.factory is not None

    def list_capabilities(self) -> list[str]:
        values = {capability.value for capability in self._registrations}
        values.update(capability.value for capability in self._extensions)
        return sorted(values)

    def list_modules(self) -> list[str]:
        return list(REGISTERED_MODULES)

    def get_provider_id(self, capability: Capability) -> str | None:
        registration = self._registrations.get(capability)
        return registration.provider_id if registration else None

    def list_plugin_capabilities(self, plugin_id: str) -> list[str]:
        registrations = self._plugin_registrations.get(plugin_id, [])
        return sorted({item.capability.value for item in registrations})

    def list_extensions(self, capability: Capability) -> list[CapabilityRegistration]:
        return list(self._extensions.get(capability, []))
