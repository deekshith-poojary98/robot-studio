from enum import Enum


class Capability(str, Enum):
    RUNNER = "runner"
    RESULTS_STORE = "results-store"
    REPORT_PROVIDER = "report-provider"
    INSTALLER = "installer"
    PACKAGE_REGISTRY = "package-registry"
    LANGUAGE_SERVICE = "language-service"
    LANGUAGE_PROVIDER = "language-provider"
    AI_PROVIDER = "ai-provider"
    TOOLBAR_ACTION = "toolbar-action"
    SIDEBAR_PANEL = "sidebar-panel"
    CONTEXT_MENU = "context-menu"
    SETTINGS_PAGE = "settings-page"
    EXPLORER_NODE_PROVIDER = "explorer-node-provider"
    GIT_PROVIDER = "git-provider"


# Aliases used in plugin manifests (kebab-case strings).
MANIFEST_CAPABILITY_ALIASES: dict[str, Capability] = {
    "runner": Capability.RUNNER,
    "results-store": Capability.RESULTS_STORE,
    "report-provider": Capability.REPORT_PROVIDER,
    "installer": Capability.INSTALLER,
    "package-registry": Capability.PACKAGE_REGISTRY,
    "language-service": Capability.LANGUAGE_SERVICE,
    "language-provider": Capability.LANGUAGE_PROVIDER,
    "ai-provider": Capability.AI_PROVIDER,
    "toolbar-action": Capability.TOOLBAR_ACTION,
    "sidebar-panel": Capability.SIDEBAR_PANEL,
    "context-menu": Capability.CONTEXT_MENU,
    "settings-page": Capability.SETTINGS_PAGE,
    "explorer-node-provider": Capability.EXPLORER_NODE_PROVIDER,
    "git-provider": Capability.GIT_PROVIDER,
}


def capability_from_manifest(value: str) -> Capability | None:
    normalized = value.strip().lower()
    if normalized in MANIFEST_CAPABILITY_ALIASES:
        return MANIFEST_CAPABILITY_ALIASES[normalized]
    try:
        return Capability(normalized)
    except ValueError:
        return None

