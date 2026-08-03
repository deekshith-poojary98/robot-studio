"""REST transport gateway — adapter between HTTP routes and application services."""

from pathlib import Path
from uuid import UUID

from robot_studio import __version__
from robot_studio.api.schemas.health import HealthResponse
from robot_studio.application.services.analysis_service import AnalysisService
from robot_studio.application.services.doctor_service import DoctorService
from robot_studio.application.services.environment_service import EnvironmentService
from robot_studio.application.services.execution_knowledge_service import (
    ExecutionKnowledgeService,
)
from robot_studio.application.services.execution_service import ExecutionService
from robot_studio.application.services.file_service import FileService
from robot_studio.application.services.index_service import IndexService
from robot_studio.application.services.language_service import LanguageFacade
from robot_studio.application.services.package_service import (
    PackageListResult,
    PackageOperationResult,
    PackageService,
)
from robot_studio.application.services.plugin_service import PluginService
from robot_studio.application.services.project_service import ProjectService
from robot_studio.application.services.report_service import ReportService
from robot_studio.application.services.test_explorer_service import (
    TestExplorerService,
    TestNode,
)
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
    PluginInfo,
    Project,
    ProjectType,
    Workspace,
)
from robot_studio.domain.models.analysis import (
    AnalysisSnapshot,
    DependencyNode,
    EdgeRef,
    EntityRef,
    InspectionInfo,
    InspectionReport,
    UsageStat,
)
from robot_studio.domain.models.doctor import (
    DoctorProfile,
    DoctorProfileId,
    DoctorReport,
    DoctorReportSummary,
    FindingProviderInfo,
)
from robot_studio.domain.models.execution_knowledge import (
    EntityExecutionStats,
    ExecutionHistoryEntry,
    ExecutionKnowledgeSnapshot,
    FlakyCandidate,
    HeatMapEntry,
    LinkedRunInfo,
    SlowEntity,
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
    def _test_explorer_service(self) -> TestExplorerService:
        service = self._container.test_explorer_service
        if service is None:
            raise RuntimeError("TestExplorerService is not initialized")
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
    def _content_search_service(self):
        service = self._container.content_search_service
        if service is None:
            raise RuntimeError("ContentSearchService is not initialized")
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

    @property
    def _analysis_service(self) -> AnalysisService:
        service = self._container.analysis_service
        if service is None:
            raise RuntimeError("AnalysisService is not initialized")
        return service

    @property
    def _execution_knowledge_service(self) -> ExecutionKnowledgeService:
        service = self._container.execution_knowledge_service
        if service is None:
            raise RuntimeError("ExecutionKnowledgeService is not initialized")
        return service

    @property
    def _doctor_service(self) -> DoctorService:
        service = self._container.doctor_service
        if service is None:
            raise RuntimeError("DoctorService is not initialized")
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

    async def create_project(self, name: str) -> Project:
        return await self._project_service.create_project(name=name)

    async def import_project(self, path: str) -> Project:
        return await self._project_service.import_project(path=path)

    async def list_projects(self) -> list[Project]:
        return await self._project_service.list_projects()

    async def open_project(self, project_id: UUID) -> Project:
        return await self._project_service.open_project(project_id=project_id)

    async def open_project_by_path(
        self,
        path: str,
        *,
        force: bool = False,
    ) -> tuple[Workspace, Project]:
        """Open a project folder as the primary UX entry.

        The selected folder becomes (or already is) the workspace root with
        ``.robotstudio/`` metadata inside it — no companion wrapper directories.

        When ``force`` is false, folders that do not look like Robot Framework
        projects are rejected so the UI can warn and offer “Continue anyways”.
        """
        from robot_studio.infrastructure.project.filesystem import (
            FilesystemProjectProvider,
            ProjectValidationError,
        )
        from robot_studio.infrastructure.workspace.filesystem import (
            find_workspace_root,
        )

        target = Path(path).expanduser().resolve()
        if not target.exists():
            raise ProjectValidationError(f"Path does not exist: '{target}'")
        if target.is_file():
            target = target.parent

        fs = FilesystemProjectProvider()
        workspace_root = find_workspace_root(target)

        # Path is inside an existing Robot Studio workspace (classic or in-project).
        if workspace_root is not None:
            workspace = await self._workspace_service.open_workspace(workspace_root)
            if target == workspace_root.resolve():
                projects = await self._project_service.list_projects()
                root_projects = [
                    item
                    for item in projects
                    if item.path.resolve() == workspace_root.resolve()
                ]
                if root_projects:
                    project = await self._project_service.open_project(
                        root_projects[0].id,
                    )
                    return workspace, project
                if projects:
                    project = await self._project_service.open_project(projects[0].id)
                    return workspace, project
                if (
                    force
                    or fs.is_robot_project(target)
                    or fs.has_manifest(target)
                ):
                    project = await self._project_service.ensure_root_project(
                        force=force,
                    )
                    return workspace, project
                raise ProjectValidationError(
                    f"Workspace '{workspace.name}' has no projects yet. "
                    "Create or import a project to continue.",
                )
            project = await self._project_service.open_project_at_path(target)
            return workspace, project

        # Standalone folder — initialize Robot Studio metadata in-place.
        if (
            not force
            and not fs.is_robot_project(target)
            and not fs.has_manifest(target)
        ):
            raise ProjectValidationError(
                f"'{target}' does not look like a Robot Framework project "
                "(expected .robot files, requirements.txt, pyproject.toml, or robot.yaml).",
            )

        workspace = await self._workspace_service.open_or_init_project_workspace(
            target,
            target.name,
        )
        project = await self._project_service.ensure_root_project(force=force)
        return workspace, project

    async def create_standalone_project(
        self,
        name: str,
        location: str,
    ) -> tuple[Workspace, Project]:
        """Create a new project folder that is also its own workspace root."""
        from robot_studio.infrastructure.project.filesystem import (
            FilesystemProjectProvider,
            ProjectValidationError,
        )

        cleaned = name.strip()
        if not cleaned:
            raise ProjectValidationError("Project name is required")

        parent = Path(location).expanduser().resolve()
        if not parent.is_dir():
            raise ProjectValidationError(
                f"Location does not exist or is not a directory: '{parent}'",
            )

        project_root = parent / cleaned
        if project_root.exists():
            raise ProjectValidationError(
                f"A folder named '{cleaned}' already exists at '{parent}'",
            )

        fs = FilesystemProjectProvider()
        project_root.mkdir(parents=True, exist_ok=True)
        fs.ensure_project_dirs(project_root)

        workspace = await self._workspace_service.open_or_init_project_workspace(
            project_root,
            cleaned,
        )
        manifest = fs.create_manifest(
            name=cleaned,
            project_type=ProjectType.EMPTY,
            project_id=workspace.id,
        )
        fs.write_manifest(project_root, manifest)
        project = await self._project_service.ensure_root_project()
        return workspace, project

    async def environment_prompt_state(
        self,
    ) -> tuple[bool, list[dict[str, str]]]:
        """Return whether the UI should prompt for an environment, plus detections."""
        try:
            environments = await self._environment_service.list_environments()
        except Exception:
            return False, []
        if environments:
            return False, []
        detected = await self._environment_service.detect_candidate_environments()
        return True, detected

    async def detect_candidate_environments(self) -> list[dict[str, str]]:
        return await self._environment_service.detect_candidate_environments()

    async def list_recent_projects(self) -> list[Project]:
        return await self._project_service.list_recent()

    async def list_environments(self, sort: str = "active") -> list[Environment]:
        return await self._environment_service.list_environments(sort=sort)

    def list_python_interpreters(self):
        return self._environment_service.list_python_interpreters()

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

    async def list_package_versions(self, name: str) -> list[str]:
        return await self._package_service.list_package_versions(name=name)

    async def get_package(self, name: str) -> InstalledPackage:
        return await self._package_service.get_package(name=name)

    async def install_package(
        self,
        name: str,
        *,
        version: str | None = None,
    ) -> PackageOperationResult:
        return await self._package_service.install_package(
            name=name,
            version=version,
        )

    async def update_package(self, name: str) -> PackageOperationResult:
        return await self._package_service.update_package(name=name)

    async def uninstall_package(self, name: str) -> PackageOperationResult:
        return await self._package_service.uninstall_package(name=name)

    async def run_file(self, file_path: str | None = None) -> ExecutionRun:
        return await self._execution_service.run_file(file_path=file_path)

    async def run_project(self, *, confirm: bool = False) -> ExecutionRun:
        await self._test_explorer_service.ensure_large_run_allowed(
            confirm=confirm,
            tag=None,
            project_wide=True,
        )
        return await self._execution_service.run_project()

    async def get_test_tree(
        self,
        query: str | None = None,
        *,
        lazy: bool = True,
    ) -> TestNode:
        return await self._test_explorer_service.get_tree(query=query, lazy=lazy)

    async def count_tests(
        self,
        *,
        tag: str | None = None,
        project_wide: bool = False,
    ) -> int:
        return await self._test_explorer_service.count_tests(
            tag=tag,
            project_wide=project_wide,
        )

    async def get_tests_for_file(self, path: str) -> list[TestNode]:
        return await self._test_explorer_service.get_file(path)

    async def run_test(self, *, file: str, name: str) -> ExecutionRun:
        return await self._test_explorer_service.run_test(file=file, name=name)

    async def run_test_suite(
        self, *, file: str | None = None, confirm: bool = False
    ) -> ExecutionRun:
        return await self._test_explorer_service.run_suite(file=file, confirm=confirm)

    async def run_tests_by_tag(self, *, tag: str, confirm: bool = False) -> ExecutionRun:
        return await self._test_explorer_service.run_tag(tag=tag, confirm=confirm)

    async def run_failed_tests(self) -> ExecutionRun:
        return await self._test_explorer_service.run_failed()

    async def run_selected_tests(self, *, tests: list[dict]) -> ExecutionRun:
        return await self._test_explorer_service.run_selected(tests=tests)

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

    async def open_report_xml(self, run_id: UUID):
        return await self._report_service.open_xml(run_id)

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

    async def search_content(
        self,
        query: str,
        *,
        limit: int = 500,
        context_lines: int = 1,
    ):
        service = self._content_search_service
        result = await service.search_content(
            query,
            limit=limit,
            context_lines=context_lines,
        )
        project = self._container.workspace_context.project if self._container.workspace_context else None
        project_id = project.id if project is not None else None
        return await service.decorate_with_index(result, project_id=project_id)

    async def language_definition(
        self,
        *,
        name: str | None = None,
        symbol_id: str | None = None,
        kind: str | None = None,
        file_path: str | None = None,
        line: int | None = None,
        column: int | None = None,
        content: str | None = None,
    ) -> dict | None:
        return await self._language_service.definition(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
            file_path=file_path,
            line=line,
            column=column,
            content=content,
        )

    async def language_references(
        self,
        *,
        name: str | None = None,
        symbol_id: str | None = None,
        kind: str | None = None,
        file_path: str | None = None,
        line: int | None = None,
        column: int | None = None,
        content: str | None = None,
    ) -> list[dict]:
        return await self._language_service.references(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
            file_path=file_path,
            line=line,
            column=column,
            content=content,
        )

    async def language_hover(
        self,
        *,
        name: str | None = None,
        symbol_id: str | None = None,
        kind: str | None = None,
        file_path: str | None = None,
        line: int | None = None,
        column: int | None = None,
        content: str | None = None,
    ) -> dict | None:
        return await self._language_service.hover(
            name=name,
            symbol_id=symbol_id,
            kind=kind,
            file_path=file_path,
            line=line,
            column=column,
            content=content,
        )

    async def language_completion(
        self,
        *,
        file_path: str,
        line: int,
        column: int,
        content: str,
        query: str = "",
    ) -> list[dict]:
        return await self._language_service.completion(
            file_path=file_path,
            line=line,
            column=column,
            content=content,
            query=query,
        )

    async def language_diagnostics(
        self,
        *,
        file_path: str,
        content: str,
    ) -> list[dict]:
        return await self._language_service.diagnostics(
            file_path=file_path,
            content=content,
        )

    async def language_format(
        self,
        *,
        file_path: str,
        content: str,
        start_line: int | None = None,
        end_line: int | None = None,
    ) -> str:
        return await self._language_service.format_document(
            file_path=file_path,
            content=content,
            start_line=start_line,
            end_line=end_line,
        )

    async def language_signature_help(
        self,
        *,
        file_path: str,
        line: int,
        column: int,
        content: str,
    ) -> dict | None:
        return await self._language_service.signature_help(
            file_path=file_path,
            line=line,
            column=column,
            content=content,
        )

    async def document_symbols(self, file_path: str) -> list[dict]:
        return await self._language_service.document_symbols(file_path)

    async def workspace_symbols(self, query: str = "", *, limit: int = 200) -> list[dict]:
        return await self._language_service.workspace_symbols(query, limit=limit)

    @property
    def _plugin_service(self) -> PluginService:
        service = self._container.plugin_service
        if service is None:
            raise RuntimeError("PluginService is not initialized")
        return service

    async def list_plugins(self) -> list[PluginInfo]:
        return await self._plugin_service.list_plugins()

    async def get_plugin(self, plugin_id: str) -> PluginInfo | None:
        return await self._plugin_service.get_plugin(plugin_id)

    async def enable_plugin(self, plugin_id: str) -> PluginInfo:
        return await self._plugin_service.enable_plugin(plugin_id)

    async def disable_plugin(self, plugin_id: str) -> PluginInfo:
        return await self._plugin_service.disable_plugin(plugin_id)

    async def reload_plugin(self, plugin_id: str) -> PluginInfo:
        return await self._plugin_service.reload_plugin(plugin_id)

    async def refresh_plugins(self) -> list[PluginInfo]:
        return await self._plugin_service.refresh()

    async def read_file(self, path: str) -> dict:
        return await self._file_service.read_file(path)

    async def write_file(self, path: str, content: str) -> dict:
        return await self._file_service.write_file(path, content)

    async def create_file(self, path: str, content: str = "") -> dict:
        return await self._file_service.create_file(path, content)

    async def create_directory(self, path: str) -> dict:
        return await self._file_service.create_directory(path)

    async def rename_path(self, path: str, new_name: str) -> dict:
        return await self._file_service.rename_path(path, new_name)

    async def move_path(self, path: str, destination_dir: str) -> dict:
        return await self._file_service.move_path(path, destination_dir)

    async def duplicate_path(self, path: str) -> dict:
        return await self._file_service.duplicate_path(path)

    async def delete_path(self, path: str) -> dict:
        return await self._file_service.delete_path(path)

    async def list_file_tree(self, path: str | None = None, *, depth: int = 0) -> list[dict]:
        return await self._file_service.list_tree(path, depth=depth)

    @property
    def _git_service(self):
        from robot_studio.application.services.git_service import GitService

        service = self._container.git_service
        if service is None:
            raise RuntimeError("GitService is not initialized")
        return service

    async def git_refresh(self):
        from robot_studio.domain.models.git import GitRepositoryInfo

        return await self._git_service.refresh()

    async def git_status(self):
        from robot_studio.domain.models.git import GitStatus

        repository = await self._git_service.get_repository()
        if repository is None:
            return None
        return await self._git_service.status()

    async def git_init(self):
        return await self._git_service.init()

    async def git_history(self, *, limit: int = 50):
        return await self._git_service.history(limit=limit)

    async def git_commit_detail(self, commit_hash: str):
        return await self._git_service.commit_detail(commit_hash)

    async def git_branches(self):
        return await self._git_service.branches()

    async def git_checkout(self, branch: str):
        return await self._git_service.checkout(branch)

    async def git_create_branch(self, name: str, *, start_point: str | None = None):
        return await self._git_service.create_branch(name, start_point=start_point)

    async def git_delete_branch(self, name: str) -> None:
        await self._git_service.delete_branch(name)

    async def git_commit(self, message: str, *, files: list[str] | None = None):
        return await self._git_service.commit(message, files=files)

    async def git_fetch(self):
        return await self._git_service.fetch()

    async def git_pull(self):
        return await self._git_service.pull()

    async def git_push(self):
        return await self._git_service.push()

    async def git_seed_local_remote(
        self,
        *,
        relative_path: str = ".test-remotes/origin.git",
        remote_name: str = "origin",
    ) -> str:
        return await self._git_service.seed_local_remote(
            relative_path=relative_path,
            remote_name=remote_name,
        )

    async def git_diff(self, *, file_path: str | None = None, commit: str | None = None):
        return await self._git_service.diff(file_path=file_path, commit=commit)

    async def analysis_snapshot(self, project_id: UUID | None = None) -> AnalysisSnapshot:
        return await self._analysis_service.snapshot(project_id)

    async def analysis_rebuild(self, project_id: UUID | None = None) -> AnalysisSnapshot:
        return await self._analysis_service.rebuild(project_id)

    def analysis_list_inspections(self) -> list[InspectionInfo]:
        return self._analysis_service.list_inspections()

    async def analysis_inspect(
        self,
        *,
        inspection_ids: list[str] | None = None,
        project_id: UUID | None = None,
    ) -> InspectionReport:
        return await self._analysis_service.inspect(
            inspection_ids=inspection_ids,
            project_id=project_id,
        )

    async def analysis_inspect_one(
        self,
        inspection_id: str,
        project_id: UUID | None = None,
    ) -> InspectionReport:
        return await self._analysis_service.inspect_one(inspection_id, project_id)

    async def analysis_keyword_callers(
        self,
        keyword: str,
        project_id: UUID | None = None,
    ) -> list[EdgeRef]:
        return await self._analysis_service.find_keyword_callers(keyword, project_id)

    async def analysis_keyword_callees(
        self,
        keyword: str,
        project_id: UUID | None = None,
    ) -> list[EdgeRef]:
        return await self._analysis_service.find_keyword_callees(keyword, project_id)

    async def analysis_dependency_graph(
        self,
        project_id: UUID | None = None,
    ) -> list[DependencyNode]:
        return await self._analysis_service.dependency_graph(project_id)

    async def analysis_affected_tests(
        self,
        *,
        changed_files: list[str] | None = None,
        changed_symbols: list[str] | None = None,
        project_id: UUID | None = None,
    ) -> list[EntityRef]:
        return await self._analysis_service.affected_tests(
            changed_files=changed_files,
            changed_symbols=changed_symbols,
            project_id=project_id,
        )

    async def analysis_variable_references(
        self,
        variable: str,
        project_id: UUID | None = None,
    ) -> list[EdgeRef]:
        return await self._analysis_service.variable_references(variable, project_id)

    async def analysis_library_usage(
        self,
        library: str | None = None,
        project_id: UUID | None = None,
    ) -> list[EdgeRef]:
        return await self._analysis_service.library_usage(library, project_id)

    async def analysis_keyword_usage_statistics(
        self,
        project_id: UUID | None = None,
    ) -> list[UsageStat]:
        return await self._analysis_service.keyword_usage_statistics(project_id)

    async def execution_knowledge_snapshot(
        self,
        project_id: UUID | None = None,
    ) -> ExecutionKnowledgeSnapshot:
        return await self._execution_knowledge_service.snapshot(project_id)

    async def execution_knowledge_link_run(self, run_id: UUID) -> LinkedRunInfo | None:
        return await self._execution_knowledge_service.link_run(run_id)

    async def execution_keyword_history(
        self,
        keyword: str,
        project_id: UUID | None = None,
        *,
        limit: int = 50,
    ) -> list[ExecutionHistoryEntry]:
        return await self._execution_knowledge_service.history_for_keyword(
            keyword,
            project_id,
            limit=limit,
        )

    async def execution_test_history(
        self,
        test: str,
        project_id: UUID | None = None,
        *,
        limit: int = 50,
    ) -> list[ExecutionHistoryEntry]:
        return await self._execution_knowledge_service.history_for_test(
            test,
            project_id,
            limit=limit,
        )

    async def execution_last_failures(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 50,
    ) -> list[ExecutionHistoryEntry]:
        return await self._execution_knowledge_service.last_failures(
            project_id,
            limit=limit,
        )

    async def execution_slowest_keywords(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 20,
    ) -> list[SlowEntity]:
        return await self._execution_knowledge_service.slowest_keywords(
            project_id,
            limit=limit,
        )

    async def execution_slowest_tests(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 20,
    ) -> list[SlowEntity]:
        return await self._execution_knowledge_service.slowest_tests(
            project_id,
            limit=limit,
        )

    async def execution_most_executed_keywords(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 20,
    ) -> list[EntityExecutionStats]:
        return await self._execution_knowledge_service.most_executed_keywords(
            project_id,
            limit=limit,
        )

    async def execution_never_executed_keywords(
        self,
        project_id: UUID | None = None,
    ) -> list[EntityRef]:
        return await self._execution_knowledge_service.never_executed_keywords(project_id)

    async def execution_heat_map(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 100,
    ) -> list[HeatMapEntry]:
        return await self._execution_knowledge_service.execution_heat_map(
            project_id,
            limit=limit,
        )

    async def execution_flaky_candidates(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 50,
    ) -> list[FlakyCandidate]:
        return await self._execution_knowledge_service.flaky_candidates(
            project_id,
            limit=limit,
        )

    def doctor_list_profiles(self) -> list[DoctorProfile]:
        return self._doctor_service.list_profiles()

    def doctor_list_providers(self) -> list[FindingProviderInfo]:
        return self._doctor_service.list_providers()

    async def doctor_run(
        self,
        *,
        profile: DoctorProfileId = DoctorProfileId.DEFAULT,
        project_id: UUID | None = None,
        provider_ids: list[str] | None = None,
    ) -> DoctorReport:
        return await self._doctor_service.run(
            profile=profile,
            project_id=project_id,
            provider_ids=provider_ids,
        )

    async def doctor_get_report(self, report_id: str) -> DoctorReport:
        return await self._doctor_service.get_report(report_id)

    async def doctor_history(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 20,
    ) -> list[DoctorReportSummary]:
        return await self._doctor_service.history(project_id, limit=limit)
