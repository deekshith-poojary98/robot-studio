"""Dependency injection container.

Wires domain interfaces to infrastructure implementations as modules are added.
"""

from dataclasses import dataclass, field
from uuid import UUID

from robot_studio.application.services.analysis_service import AnalysisService
from robot_studio.application.services.doctor_service import DoctorService
from robot_studio.application.services.environment_service import EnvironmentService
from robot_studio.application.services.execution_knowledge_service import (
    ExecutionKnowledgeService,
)
from robot_studio.application.services.execution_service import ExecutionService
from robot_studio.application.services.file_service import FileService
from robot_studio.application.services.git_service import GitService
from robot_studio.application.services.index_service import IndexService
from robot_studio.application.services.insights_service import InsightsService
from robot_studio.application.services.language_service import LanguageFacade
from robot_studio.application.services.package_service import PackageService
from robot_studio.application.services.plugin_service import PluginService
from robot_studio.application.services.project_service import ProjectService
from robot_studio.application.services.report_service import ReportService
from robot_studio.application.services.run_configuration_service import (
    RunConfigurationService,
)
from robot_studio.application.services.settings_service import SettingsService
from robot_studio.application.services.test_explorer_service import TestExplorerService
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.application.services.workspace_event_service import WorkspaceEventService
from robot_studio.application.services.workspace_service import WorkspaceService
from robot_studio.core.config import settings
from robot_studio.core.events import EventBus, InMemoryEventBus
from robot_studio.core.plugins import PluginHost
from robot_studio.domain.interfaces.plugins import Capability
from robot_studio.infrastructure.analysis.engine import RobotAnalysisEngine
from robot_studio.infrastructure.analysis.execution_store import SqliteExecutionKnowledgeStore
from robot_studio.infrastructure.analysis.inspections_engine import InspectionEngine
from robot_studio.infrastructure.analysis.sqlite_analysis_store import SqliteAnalysisStore
from robot_studio.infrastructure.doctor.store import SqliteDoctorStore
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
from robot_studio.infrastructure.language.completion import SqliteCompletionUsageStore
from robot_studio.infrastructure.packages.pip_installer import PipInstaller
from robot_studio.infrastructure.packages.pypi_provider import PyPIProvider
from robot_studio.infrastructure.plugins.builtins import register_builtin_capabilities
from robot_studio.infrastructure.plugins.html_report_provider import HtmlReportProvider
from robot_studio.infrastructure.plugins.plugin_manager import PluginManager
from robot_studio.infrastructure.project.filesystem import FilesystemProjectProvider
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
    run_configuration_service: RunConfigurationService | None = field(
        default=None,
        init=False,
    )
    test_explorer_service: TestExplorerService | None = field(default=None, init=False)
    report_service: ReportService | None = field(default=None, init=False)
    insights_service: InsightsService | None = field(default=None, init=False)
    index_store: SqliteIndexStore | None = field(default=None, init=False)
    analysis_store: SqliteAnalysisStore | None = field(default=None, init=False)
    analysis_engine: RobotAnalysisEngine | None = field(default=None, init=False)
    inspection_engine: InspectionEngine | None = field(default=None, init=False)
    analysis_service: AnalysisService | None = field(default=None, init=False)
    execution_knowledge_store: SqliteExecutionKnowledgeStore | None = field(
        default=None,
        init=False,
    )
    execution_knowledge_service: ExecutionKnowledgeService | None = field(
        default=None,
        init=False,
    )
    doctor_store: SqliteDoctorStore | None = field(default=None, init=False)
    doctor_service: DoctorService | None = field(default=None, init=False)
    index_service: IndexService | None = field(default=None, init=False)
    content_search_service: object | None = field(default=None, init=False)
    symbol_search_provider: object | None = field(default=None, init=False)
    search_providers: list = field(default_factory=list, init=False)
    language_service: RobotLanguageService | None = field(default=None, init=False)
    language_facade: LanguageFacade | None = field(default=None, init=False)
    file_service: FileService | None = field(default=None, init=False)
    git_service: GitService | None = field(default=None, init=False)
    workspace_event_service: WorkspaceEventService | None = field(
        default=None,
        init=False,
    )
    plugin_manager: PluginManager | None = field(default=None, init=False)
    plugin_service: PluginService | None = field(default=None, init=False)
    settings_service: SettingsService | None = field(default=None, init=False)
    _initialized: bool = field(default=False, init=False)

    def initialize(self) -> None:
        if self._initialized:
            return

        register_builtin_capabilities(self.plugin_host)

        self.settings_service = SettingsService(
            data_dir=settings.data_dir,
            event_bus=self.event_bus,
        )
        self.settings_service.load()

        installer = PipInstaller()
        registry = PyPIProvider(cache_dir=settings.data_dir / "cache")
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
        self.run_configuration_service = RunConfigurationService(
            context=self.workspace_context,
        )
        self.workspace_repository = SqliteWorkspaceRepository(settings.database_path)
        self.workspace_service = WorkspaceService(
            repository=self.workspace_repository,
            context=self.workspace_context,
        )

        filesystem = FilesystemProjectProvider()
        self.project_repository = SqliteProjectRepository(settings.database_path)
        self.project_service = ProjectService(
            repository=self.project_repository,
            context=self.workspace_context,
            event_bus=self.event_bus,
            filesystem=filesystem,
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
        self.environment_service.start()

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
            environment_repository=self.environment_repository,
            run_configuration_service=self.run_configuration_service,
        )
        self.report_service = ReportService(
            context=self.workspace_context,
            event_bus=self.event_bus,
            results_store=self.plugin_host.get(Capability.RESULTS_STORE),
            repository=self.execution_repository,
        )
        self.report_service.start()

        self.index_store = SqliteIndexStore(settings.database_path)
        self.analysis_store = SqliteAnalysisStore(settings.database_path)
        self.analysis_engine = RobotAnalysisEngine(
            store=self.analysis_store,
            event_bus=self.event_bus,
        )
        self.inspection_engine = InspectionEngine(
            analysis_engine=self.analysis_engine,
            store=self.analysis_store,
        )
        indexer = FilesystemIndexer(
            store=self.index_store,
            analysis_engine=self.analysis_engine,
        )
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
        self.insights_service = InsightsService(
            context=self.workspace_context,
            index_store=self.index_store,
            execution_repository=self.execution_repository,
        )
        from robot_studio.application.services.content_search_service import (
            ContentSearchService,
        )
        from robot_studio.application.services.symbol_search_provider import (
            IndexSymbolSearchProvider,
        )

        self.content_search_service = ContentSearchService(
            context=self.workspace_context,
            index_store=self.index_store,
            settings_service=self.settings_service,
        )
        self.symbol_search_provider = IndexSymbolSearchProvider(self.index_service)
        self.search_providers = [
            self.content_search_service,
            self.symbol_search_provider,
        ]
        self.analysis_service = AnalysisService(
            context=self.workspace_context,
            engine=self.analysis_engine,
            inspection_engine=self.inspection_engine,
            project_repository=self.project_repository,
        )
        self.execution_knowledge_store = SqliteExecutionKnowledgeStore(
            settings.database_path,
        )
        self.execution_knowledge_service = ExecutionKnowledgeService(
            context=self.workspace_context,
            event_bus=self.event_bus,
            analysis_store=self.analysis_store,
            execution_store=self.execution_knowledge_store,
            execution_repository=self.execution_repository,
        )
        self.execution_knowledge_service.start()

        self.doctor_store = SqliteDoctorStore(settings.database_path)
        self.doctor_service = DoctorService(
            context=self.workspace_context,
            analysis_engine=self.analysis_engine,
            analysis_store=self.analysis_store,
            store=self.doctor_store,
            project_repository=self.project_repository,
            execution_knowledge=self.execution_knowledge_service,
        )

        self.workspace_event_service = WorkspaceEventService(
            context=self.workspace_context,
            event_bus=self.event_bus,
            watcher=watcher,
            on_workspace_missing=self._purge_on_workspace_missing,
        )
        self.workspace_event_service.start()

        self.test_explorer_service = TestExplorerService(
            context=self.workspace_context,
            event_bus=self.event_bus,
            store=self.index_store,
            project_service=self.project_service,
            execution_service=self.execution_service,
            settings_service=self.settings_service,
        )
        self.test_explorer_service.start()

        language = RobotLanguageService(
            store=self.index_store,
            context=self.workspace_context,
            event_bus=self.event_bus,
            settings_service=self.settings_service,
            analysis_engine=self.analysis_engine,
            usage_store=SqliteCompletionUsageStore(
                settings.data_dir / "completion-usage.db",
            ),
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
        assert self.analysis_store is not None
        assert self.execution_knowledge_store is not None
        assert self.doctor_store is not None
        assert self.plugin_manager is not None
        await self.workspace_repository.initialize()
        await self.project_repository.initialize()
        await self.environment_repository.initialize()
        await self.execution_repository.initialize()
        await self.index_store.initialize()
        await self.analysis_store.initialize()
        await self.execution_knowledge_store.initialize()
        await self.doctor_store.initialize()
        if self.language_service is not None and self.language_service.usage_store is not None:
            await self.language_service.usage_store.ensure_schema()
        await self.plugin_manager.initialize()

    async def _purge_on_workspace_missing(self, workspace_id: UUID) -> int:
        """Drop orphaned registry rows and clear the dead session.

        Leaving the context open after the root vanishes keeps Git / files /
        environments APIs pointed at a path that no longer exists, which the
        UI then hammers while the "workspace missing" dialog is up.
        """
        removed = 0
        try:
            if self.environment_service is not None:
                removed += await self.environment_service.purge_workspace_environments(
                    workspace_id,
                )
            if self.report_service is not None:
                removed += await self.report_service.purge_workspace_runs(workspace_id)
        finally:
            # Always clear the session — purge can fail if the DB is unavailable
            # (e.g. tests without a data_dir), but the UI still needs a clean slate.
            if (
                self.workspace_context is not None
                and self.workspace_context.workspace_id == workspace_id
            ):
                await self.workspace_context.close()
        return removed

    async def shutdown(self) -> None:
        """Release background work started by initialize/open.

        Safe to call more than once, and safe to call when nothing was opened.
        """
        if self.execution_knowledge_service is not None:
            await self.execution_knowledge_service.stop()
        if self.git_service is not None:
            await self.git_service.stop()
        if self.workspace_event_service is not None:
            await self.workspace_event_service.stop()
        if self.environment_service is not None:
            self.environment_service.stop()
        if self.index_service is not None:
            await self.index_service.stop()
        if self.workspace_context is not None:
            await self.workspace_context.close()


container = Container()
