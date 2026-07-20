"""Dependency injection container.

Wires domain interfaces to infrastructure implementations as modules are added.
"""

from dataclasses import dataclass, field

from robot_studio.application.services.environment_service import EnvironmentService
from robot_studio.application.services.execution_service import ExecutionService
from robot_studio.application.services.file_service import FileService
from robot_studio.application.services.git_service import GitService
from robot_studio.application.services.index_service import IndexService
from robot_studio.application.services.language_service import LanguageFacade
from robot_studio.application.services.package_service import PackageService
from robot_studio.application.services.plugin_service import PluginService
from robot_studio.application.services.project_service import ProjectService
from robot_studio.application.services.report_service import ReportService
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.application.services.workspace_service import WorkspaceService
from robot_studio.core.config import settings
from robot_studio.core.events import EventBus, InMemoryEventBus
from robot_studio.core.plugins import PluginHost
from robot_studio.domain.interfaces.plugins import Capability
from robot_studio.infrastructure.environment.filesystem import (
    FilesystemEnvironmentProvider,
)
from robot_studio.infrastructure.environment.python_provider import (
    PythonEnvironmentProvider,
)
from robot_studio.infrastructure.execution.results_store import FilesystemResultsStore
from robot_studio.infrastructure.git.cli_provider import CliGitProvider
from robot_studio.infrastructure.execution.subprocess_runner import SubprocessRunner
from robot_studio.infrastructure.indexing.file_watcher import NativeFileWatcher, PollingFileWatcher
from robot_studio.infrastructure.indexing.filesystem_indexer import FilesystemIndexer
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.robot_language_service import (
    RobotLanguageService,
)
from robot_studio.infrastructure.packages.pip_installer import PipInstaller
from robot_studio.infrastructure.packages.pypi_provider import PyPIProvider
from robot_studio.infrastructure.plugins.builtins import register_builtin_capabilities
from robot_studio.infrastructure.plugins.html_report_provider import HtmlReportProvider
from robot_studio.infrastructure.plugins.plugin_manager import PluginManager
from robot_studio.infrastructure.project.filesystem import FilesystemProjectProvider
from robot_studio.infrastructure.project.templates import TemplateService
from robot_studio.infrastructure.repositories.environment_repository import (
    SqliteEnvironmentRepository,
)
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
)
from robot_studio.infrastructure.repositories.project_repository import (
    SqliteProjectRepository,
)
from robot_studio.infrastructure.repositories.workspace_repository import (
    SqliteWorkspaceRepository,
)


@dataclass
class Container:
    """Application-wide service container."""

    event_bus: EventBus = field(default_factory=InMemoryEventBus)
    plugin_host: PluginHost = field(default_factory=PluginHost)
    workspace_context: WorkspaceContext | None = field(default=None, init=False)
    workspace_repository: SqliteWorkspaceRepository | None = field(
        default=None,
        init=False,
    )
    workspace_service: WorkspaceService | None = field(default=None, init=False)
    project_repository: SqliteProjectRepository | None = field(
        default=None,
        init=False,
    )
    project_service: ProjectService | None = field(default=None, init=False)
    environment_repository: SqliteEnvironmentRepository | None = field(
        default=None,
        init=False,
    )
    environment_service: EnvironmentService | None = field(default=None, init=False)
    package_service: PackageService | None = field(default=None, init=False)
    execution_repository: SqliteExecutionRepository | None = field(
        default=None,
        init=False,
    )
    execution_service: ExecutionService | None = field(default=None, init=False)
    report_service: ReportService | None = field(default=None, init=False)
    index_store: SqliteIndexStore | None = field(default=None, init=False)
    index_service: IndexService | None = field(default=None, init=False)
    language_service: RobotLanguageService | None = field(default=None, init=False)
    language_facade: LanguageFacade | None = field(default=None, init=False)
    file_service: FileService | None = field(default=None, init=False)
    git_service: GitService | None = field(default=None, init=False)
    plugin_manager: PluginManager | None = field(default=None, init=False)
    plugin_service: PluginService | None = field(default=None, init=False)
    _initialized: bool = field(default=False, init=False)

    def initialize(self) -> None:
        if self._initialized:
            return

        register_builtin_capabilities(self.plugin_host)

        installer = PipInstaller()
        registry = PyPIProvider()
        self.plugin_host.register(
            Capability.INSTALLER,
            "pip-installer",
            factory=lambda: installer,
            plugin_id="pip-installer",
        )
        self.plugin_host.register(
            Capability.PACKAGE_REGISTRY,
            "pypi-registry",
            factory=lambda: registry,
            plugin_id="pypi-registry",
        )

        self.workspace_context = WorkspaceContext(self.event_bus)
        self.workspace_repository = SqliteWorkspaceRepository(settings.database_path)
        self.workspace_service = WorkspaceService(
            repository=self.workspace_repository,
            context=self.workspace_context,
        )

        filesystem = FilesystemProjectProvider()
        templates = TemplateService(filesystem)
        self.project_repository = SqliteProjectRepository(settings.database_path)
        self.project_service = ProjectService(
            repository=self.project_repository,
            context=self.workspace_context,
            event_bus=self.event_bus,
            filesystem=filesystem,
            templates=templates,
        )

        env_fs = FilesystemEnvironmentProvider()
        env_python = PythonEnvironmentProvider()
        self.environment_repository = SqliteEnvironmentRepository(settings.database_path)
        self.environment_service = EnvironmentService(
            repository=self.environment_repository,
            context=self.workspace_context,
            event_bus=self.event_bus,
            filesystem=env_fs,
            python=env_python,
        )

        self.package_service = PackageService(
            context=self.workspace_context,
            event_bus=self.event_bus,
            installer=self.plugin_host.get(Capability.INSTALLER),
            registry=self.plugin_host.get(Capability.PACKAGE_REGISTRY),
        )

        runner = SubprocessRunner()
        results_store = FilesystemResultsStore()
        report_provider = HtmlReportProvider()
        self.plugin_host.register(
            Capability.RUNNER,
            "robot-cli-runner",
            factory=lambda: runner,
            plugin_id="robot-cli-runner",
        )
        self.plugin_host.register(
            Capability.RESULTS_STORE,
            "output-xml-results-store",
            factory=lambda: results_store,
            plugin_id="output-xml-results-store",
        )
        self.plugin_host.register(
            Capability.REPORT_PROVIDER,
            "builtin-html-report-provider",
            factory=lambda: report_provider,
            plugin_id="builtin-html-report-provider",
        )
        self.execution_repository = SqliteExecutionRepository(settings.database_path)
        self.execution_service = ExecutionService(
            context=self.workspace_context,
            event_bus=self.event_bus,
            runner=self.plugin_host.get(Capability.RUNNER),
            results_store=self.plugin_host.get(Capability.RESULTS_STORE),
            repository=self.execution_repository,
        )
        self.report_service = ReportService(
            context=self.workspace_context,
            event_bus=self.event_bus,
            results_store=self.plugin_host.get(Capability.RESULTS_STORE),
            repository=self.execution_repository,
        )
        self.report_service.start()

        self.index_store = SqliteIndexStore(settings.database_path)
        indexer = FilesystemIndexer(store=self.index_store)
        watcher = NativeFileWatcher()
        self.index_service = IndexService(
            context=self.workspace_context,
            event_bus=self.event_bus,
            store=self.index_store,
            indexer=indexer,
            watcher=watcher,
            project_repository=self.project_repository,
        )
        self.index_service.start()

        language = RobotLanguageService(
            store=self.index_store,
            context=self.workspace_context,
            event_bus=self.event_bus,
        )
        self.plugin_host.register(
            Capability.LANGUAGE_SERVICE,
            "robot-language-service",
            factory=lambda: language,
            plugin_id="robot-language-service",
        )
        self.plugin_host.register(
            Capability.LANGUAGE_PROVIDER,
            "robot-language-service",
            factory=lambda: language,
            plugin_id="robot-language-service",
        )
        self.language_service = language
        self.language_service.start()
        self.language_facade = LanguageFacade(
            context=self.workspace_context,
            language=self.plugin_host.get(Capability.LANGUAGE_SERVICE),
        )
        git_provider = CliGitProvider()
        self.plugin_host.register(
            Capability.GIT_PROVIDER,
            "git-cli-provider",
            factory=lambda: git_provider,
            plugin_id="git-cli-provider",
        )
        self.git_service = GitService(
            context=self.workspace_context,
            event_bus=self.event_bus,
            provider=self.plugin_host.get(Capability.GIT_PROVIDER),
        )
        self.git_service.start()
        self.file_service = FileService(
            context=self.workspace_context,
            event_bus=self.event_bus,
        )

        self.plugin_manager = PluginManager(
            plugin_host=self.plugin_host,
            event_bus=self.event_bus,
            workspace_context=self.workspace_context,
            settings=settings,
            project_service=self.project_service,
            environment_service=self.environment_service,
            execution_service=self.execution_service,
            language_facade=self.language_facade,
            storage_root=settings.data_dir / "plugin-storage",
        )
        self.plugin_manager.configure_state_path(settings.data_dir / "plugins" / "state.json")
        self.plugin_service = PluginService(manager=self.plugin_manager)
        self._initialized = True

    async def initialize_async(self) -> None:
        self.initialize()
        assert self.workspace_repository is not None
        assert self.project_repository is not None
        assert self.environment_repository is not None
        assert self.execution_repository is not None
        assert self.index_store is not None
        assert self.plugin_manager is not None
        await self.workspace_repository.initialize()
        await self.project_repository.initialize()
        await self.environment_repository.initialize()
        await self.execution_repository.initialize()
        await self.index_store.initialize()
        await self.plugin_manager.initialize()


container = Container()
