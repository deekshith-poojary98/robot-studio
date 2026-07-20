"""Built-in capability registrations."""

from robot_studio.core.plugins import PluginHost
from robot_studio.domain.interfaces.plugins import Capability


def register_builtin_capabilities(plugin_host: PluginHost) -> None:
    """Register built-in providers. Factories are wired as modules land."""
    plugin_host.register(Capability.RUNNER, "robot-cli-runner")
    plugin_host.register(Capability.RESULTS_STORE, "output-xml-results-store")
    plugin_host.register(Capability.REPORT_PROVIDER, "builtin-html-report-provider")
    plugin_host.register(Capability.INSTALLER, "pip-installer")
    plugin_host.register(Capability.PACKAGE_REGISTRY, "pypi-registry")
    plugin_host.register(Capability.LANGUAGE_SERVICE, "robot-language-service")
    plugin_host.register(Capability.GIT_PROVIDER, "git-cli-provider")
