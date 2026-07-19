"""REST transport gateway — adapter between HTTP routes and application services."""

from uuid import UUID

from robot_studio import __version__
from robot_studio.api.schemas.health import HealthResponse
from robot_studio.application.services.environment_service import EnvironmentService
from robot_studio.application.services.execution_service import ExecutionService
from robot_studio.application.services.file_service import FileService
from robot_studio.application.services.index_service import IndexService
from robot_studio.application.services.language_service import LanguageFacade
from robot_studio.application.services.package_service import (
    PackageListResult,
    PackageOperationResult,
    PackageService,
)
from robot_studio.application.services.project_service import ProjectService
from robot_studio.application.services.report_service import ReportService
from robot_studio.application.services.workspace_service import WorkspaceService
from robot_studio.core.container import Container
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import (
    DashboardSummary,
    Environment,
    ExecutionRun,
    IndexStatus,
    InstalledPackage,
    PackageSearchResult,
    Project,
    ProjectType,
    Workspace,
)


class RestGateway:
    """Thin REST adapter delegating to the application layer."""

    def __init__(self, container: Container) -> None:
        self._container = container

    @property
    def _workspace_service(self) -> WorkspaceService:
        service = self._container.workspace_service
        if service is None:
            raise RuntimeError("WorkspaceService is not initialized")
        return service

    @property
    def _project_service(self) -> ProjectService:
        service = self._container.project_service
        if service is None:
            raise RuntimeError("ProjectService is not initialized")
        return service

    @property
    def _environment_service(self) -> EnvironmentService:
        service = self._container.environment_service
        if service is None:
            raise RuntimeError("EnvironmentService is not initialized")
        return service

    @property
    def _package_service(self) -> PackageService:
        service = self._container.package_service
        if service is None:
            raise RuntimeError("PackageService is not initialized")
        return service

    @property
    def _execution_service(self) -> ExecutionService:
        service = self._container.execution_service
        if service is None:
            raise RuntimeError("ExecutionService is not initialized")
        return service

    @property
    def _report_service(self) -> ReportService:
        service = self._container.report_service
        if service is None:
            raise RuntimeError("ReportService is not initialized")
        return service

    @property
    def _index_service(self) -> IndexService:
        service = self._container.index_service
        if service is None:
            raise RuntimeError("IndexService is not initialized")
        return service

    @property
    def _language_service(self) -> LanguageFacade:
        service = self._container.language_facade
        if service is None:
            raise RuntimeError("LanguageFacade is not initialized")
        return service

    @property
    def _file_service(self) -> FileService:
        service = self._container.file_service
        if service is None:
            raise RuntimeError("FileService is not initialized")
        return service

    async def health(self) -> HealthResponse:
        return HealthResponse(
            status="ok",
            version=__version__,
            modules=self._container.plugin_host.list_modules(),
        )

    async def create_workspace(self, name: str, location: str) -> Workspace:
        return await self._workspace_service.create_workspace(
            name=name,
            location=location,
        )

    async def open_workspace(self, path: str) -> Workspace:
        return await self._workspace_service.open_workspace(path=path)

    async def list_recent_workspaces(self) -> list[Workspace]:
        return await self._workspace_service.list_recent()

    async def create_project(self, name: str, project_type: ProjectType) -> Project:
        return await self._project_service.create_project(
            name=name,
            project_type=project_type,
        )

    async def import_project(self, path: str) -> Project:
        return await self._project_service.import_project(path=path)

    async def list_projects(self) -> list[Project]:
        return await self._project_service.list_projects()

    async def open_project(self, project_id: UUID) -> Project:
        return await self._project_service.open_project(project_id=project_id)

    async def list_recent_projects(self) -> list[Project]:
        return await self._project_service.list_recent()

    async def list_environments(self, sort: str = "active") -> list[Environment]:
        return await self._environment_service.list_environments(sort=sort)

    async def create_environment(
        self,
        name: str,
        python_interpreter: str,
        *,
        install_robot_framework: bool = False,
    ) -> Environment:
        return await self._environment_service.create_environment(
            name=name,
            python_interpreter=python_interpreter,
            install_robot_framework=install_robot_framework,
        )

    async def import_environment(self, path: str) -> Environment:
        return await self._environment_service.import_environment(path=path)

    async def activate_environment(self, environment_id: UUID) -> Environment:
        return await self._environment_service.activate_environment(
            environment_id=environment_id,
        )

    async def get_environment(self, environment_id: UUID) -> Environment:
        return await self._environment_service.get_environment(
            environment_id=environment_id,
        )

    async def clone_environment(
        self,
        environment_id: UUID,
        name: str,
    ) -> Environment:
        return await self._environment_service.clone_environment(
            environment_id=environment_id,
            name=name,
        )

    async def delete_environment(
        self,
        environment_id: UUID,
        *,
        delete_files: bool = False,
    ) -> None:
        await self._environment_service.delete_environment(
            environment_id=environment_id,
            delete_files=delete_files,
        )

    async def list_packages(
        self,
        query: str | None = None,
        sort: str = "name",
    ) -> PackageListResult:
        return await self._package_service.list_packages(query=query, sort=sort)

    async def search_packages(self, query: str) -> list[PackageSearchResult]:
        return await self._package_service.search_packages(query=query)

    async def get_package(self, name: str) -> InstalledPackage:
        return await self._package_service.get_package(name=name)

    async def install_package(self, name: str) -> PackageOperationResult:
        return await self._package_service.install_package(name=name)

    async def update_package(self, name: str) -> PackageOperationResult:
        return await self._package_service.update_package(name=name)

    async def uninstall_package(self, name: str) -> PackageOperationResult:
        return await self._package_service.uninstall_package(name=name)

    async def run_file(self, file_path: str | None = None) -> ExecutionRun:
        return await self._execution_service.run_file(file_path=file_path)

    async def run_project(self) -> ExecutionRun:
        return await self._execution_service.run_project()

    async def stop_execution(self) -> ExecutionRun | None:
        return await self._execution_service.stop()

    async def get_execution_status(self) -> ExecutionRun | None:
        return await self._execution_service.get_status()

    async def list_execution_history(self) -> list[ExecutionRun]:
        return await self._execution_service.list_history()

    async def list_reports(self) -> list[ExecutionRun]:
        return await self._report_service.list_runs()

    async def get_report(self, run_id: UUID) -> ExecutionRun:
        return await self._report_service.get_run(run_id)

    async def delete_report(self, run_id: UUID) -> None:
        await self._report_service.delete_run(run_id)

    async def open_report_log(self, run_id: UUID):
        return await self._report_service.open_log(run_id)

    async def open_report_html(self, run_id: UUID):
        return await self._report_service.open_report(run_id)

    async def reveal_report(self, run_id: UUID):
        return await self._report_service.reveal(run_id)

    async def get_reports_dashboard(self) -> DashboardSummary:
        return await self._report_service.dashboard()

    async def rebuild_index(self) -> IndexStatus:
        return await self._index_service.rebuild()

    async def get_index_status(self) -> IndexStatus:
        return await self._index_service.get_status()

    async def search_symbols(
        self,
        query: str,
        *,
        kind: SymbolKind | None = None,
        limit: int = 100,
    ) -> list[dict]:
        return await self._index_service.search(query, kind=kind, limit=limit)

    async def language_definition(
        self,
        *,
        name: str | None = None,
        symbol_id: str | None = None,
        kind: str | None = None,
    ) -> dict | None:
        return await self._language_service.definition(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
        )

    async def language_references(
        self,
        *,
        name: str | None = None,
        symbol_id: str | None = None,
        kind: str | None = None,
    ) -> list[dict]:
        return await self._language_service.references(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
        )

    async def language_hover(
        self,
        *,
        name: str | None = None,
        symbol_id: str | None = None,
        kind: str | None = None,
    ) -> dict | None:
        return await self._language_service.hover(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
        )

    async def document_symbols(self, file_path: str) -> list[dict]:
        return await self._language_service.document_symbols(file_path)

    async def workspace_symbols(self, query: str = "", *, limit: int = 200) -> list[dict]:
        return await self._language_service.workspace_symbols(query, limit=limit)

    async def read_file(self, path: str) -> dict:
        return await self._file_service.read_file(path)

    async def write_file(self, path: str, content: str) -> dict:
        return await self._file_service.write_file(path, content)

    async def list_file_tree(self, path: str | None = None, *, depth: int = 3) -> list[dict]:
        return await self._file_service.list_tree(path, depth=depth)
