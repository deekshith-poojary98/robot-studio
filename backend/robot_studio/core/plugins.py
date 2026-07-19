"""Plugin host and capability registry."""

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


@dataclass
class PluginHost:
    """Registry for built-in and future plugin capability providers."""

    _registrations: dict[Capability, CapabilityRegistration] = field(
        default_factory=dict,
    )

    def register(
        self,
        capability: Capability,
        provider_id: str,
        factory: CapabilityFactory | None = None,
    ) -> None:
        self._registrations[capability] = CapabilityRegistration(
            capability=capability,
            provider_id=provider_id,
            factory=factory,
        )

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
        return sorted(capability.value for capability in self._registrations)

    def list_modules(self) -> list[str]:
        return list(REGISTERED_MODULES)

    def get_provider_id(self, capability: Capability) -> str | None:
        registration = self._registrations.get(capability)
        return registration.provider_id if registration else None
