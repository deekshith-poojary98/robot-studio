"""Built-in plugin metadata and lifecycle adapters."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from robot_studio.domain.interfaces.plugins import Capability
from robot_studio.domain.models.plugin import PluginManifest


@dataclass(frozen=True)
class BuiltinPluginSpec:
    manifest: PluginManifest
    capabilities: list[Capability]


class BuiltinPluginAdapter:
    """Lifecycle adapter for built-in capability providers."""

    def __init__(self, spec: BuiltinPluginSpec) -> None:
        self.spec = spec

    async def initialize(self, context: Any) -> None:
        return None

    async def activate(self, context: Any) -> None:
        return None

    async def deactivate(self, context: Any) -> None:
        return None

    async def dispose(self, context: Any) -> None:
        return None


BUILTIN_PLUGIN_SPECS: list[BuiltinPluginSpec] = [
    BuiltinPluginSpec(
        manifest=PluginManifest(
            id="pip-installer",
            name="Pip Installer",
            version="1.0.0",
            author="Robot Studio",
            description="Installs Python packages into workspace environments.",
            entry="builtin",
            capabilities=["installer"],
        ),
        capabilities=[Capability.INSTALLER],
    ),
    BuiltinPluginSpec(
        manifest=PluginManifest(
            id="pypi-registry",
            name="PyPI Registry",
            version="1.0.0",
            author="Robot Studio",
            description="Searches and resolves packages from PyPI.",
            entry="builtin",
            capabilities=["package-registry"],
        ),
        capabilities=[Capability.PACKAGE_REGISTRY],
    ),
    BuiltinPluginSpec(
        manifest=PluginManifest(
            id="robot-cli-runner",
            name="Robot CLI Runner",
            version="1.0.0",
            author="Robot Studio",
            description="Executes Robot Framework suites via subprocess.",
            entry="builtin",
            capabilities=["runner"],
        ),
        capabilities=[Capability.RUNNER],
    ),
    BuiltinPluginSpec(
        manifest=PluginManifest(
            id="output-xml-results-store",
            name="Output XML Results Store",
            version="1.0.0",
            author="Robot Studio",
            description="Indexes execution output artifacts from the filesystem.",
            entry="builtin",
            capabilities=["results-store"],
        ),
        capabilities=[Capability.RESULTS_STORE],
    ),
    BuiltinPluginSpec(
        manifest=PluginManifest(
            id="builtin-html-report-provider",
            name="HTML Report Provider",
            version="1.0.0",
            author="Robot Studio",
            description="Serves Robot Framework HTML and XML report artifacts.",
            entry="builtin",
            capabilities=["report-provider"],
        ),
        capabilities=[Capability.REPORT_PROVIDER],
    ),
    BuiltinPluginSpec(
        manifest=PluginManifest(
            id="robot-language-service",
            name="Robot Language Service",
            version="1.0.0",
            author="Robot Studio",
            description="Provides Robot Framework language intelligence.",
            entry="builtin",
            capabilities=["language-service", "language-provider"],
        ),
        capabilities=[Capability.LANGUAGE_SERVICE, Capability.LANGUAGE_PROVIDER],
    ),
    BuiltinPluginSpec(
        manifest=PluginManifest(
            id="report-service",
            name="Report Service",
            version="1.0.0",
            author="Robot Studio",
            description="Indexes runs and opens report artifacts after execution.",
            entry="builtin",
            capabilities=[],
        ),
        capabilities=[],
    ),
]


def builtin_specs_by_id() -> dict[str, BuiltinPluginSpec]:
    return {spec.manifest.id: spec for spec in BUILTIN_PLUGIN_SPECS}
