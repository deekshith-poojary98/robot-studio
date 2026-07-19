from enum import Enum


class Capability(str, Enum):
    RUNNER = "runner"
    RESULTS_STORE = "results-store"
    REPORT_PROVIDER = "report-provider"
    INSTALLER = "installer"
    PACKAGE_REGISTRY = "package-registry"
    LANGUAGE_SERVICE = "language-service"
    AI_PROVIDER = "ai-provider"
