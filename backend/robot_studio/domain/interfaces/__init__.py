"""Domain port interfaces.

Each module defines an abstract interface that infrastructure implements.
"""

from robot_studio.domain.interfaces.environment import EnvironmentRepository
from robot_studio.domain.interfaces.indexing import IndexScope, IndexStore, SymbolKind
from robot_studio.domain.interfaces.installer import Installer, PackageRegistry
from robot_studio.domain.interfaces.language import LanguageService
from robot_studio.domain.interfaces.plugins import Capability
from robot_studio.domain.interfaces.project import ProjectRepository
from robot_studio.domain.interfaces.runner import ReportProvider, ResultsStore, Runner
from robot_studio.domain.interfaces.workspace import WorkspaceRepository

__all__ = [
    "Capability",
    "EnvironmentRepository",
    "IndexScope",
    "IndexStore",
    "Installer",
    "LanguageService",
    "PackageRegistry",
    "ProjectRepository",
    "ReportProvider",
    "ResultsStore",
    "Runner",
    "SymbolKind",
    "WorkspaceRepository",
]
