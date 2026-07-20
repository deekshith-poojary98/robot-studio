"""Domain entities."""

from datetime import datetime
from enum import Enum
from pathlib import Path
from uuid import UUID

from pydantic import BaseModel, Field


class ExecutionStatus(str, Enum):
    IDLE = "idle"
    STARTING = "starting"
    RUNNING = "running"
    STOPPING = "stopping"
    FINISHED = "finished"
    FAILED = "failed"
    CANCELLED = "cancelled"


class ProjectType(str, Enum):
    BROWSER = "browser"
    API = "api"
    SELENIUM = "selenium"
    EMPTY = "empty"
    IMPORTED = "imported"


class WorkspaceSettings(BaseModel):
    default_environment_id: UUID | None = None
    robot_options: list[str] = Field(default_factory=list)


class Workspace(BaseModel):
    id: UUID
    name: str
    path: Path
    created_at: datetime
    settings: WorkspaceSettings = Field(default_factory=WorkspaceSettings)


class Project(BaseModel):
    id: UUID
    workspace_id: UUID
    name: str
    path: Path
    created_at: datetime
    type: ProjectType = ProjectType.EMPTY


class Environment(BaseModel):
    id: UUID
    workspace_id: UUID
    name: str
    path: Path
    python_version: str
    python_executable: Path
    pip_executable: Path
    robot_executable: Path | None = None
    created_at: datetime
    is_active: bool = False
    robot_version: str | None = None
    package_count: int = 0
    platform: str | None = None
    architecture: str | None = None


class InstalledPackage(BaseModel):
    name: str
    version: str
    latest_version: str | None = None
    summary: str | None = None
    author: str | None = None
    homepage: str | None = None
    license: str | None = None
    location: str | None = None
    requires: list[str] = Field(default_factory=list)
    update_available: bool = False


class PackageSearchResult(BaseModel):
    name: str
    latest_version: str
    summary: str | None = None


class Keyword(BaseModel):
    name: str
    library: str
    arguments: list[str] = Field(default_factory=list)
    documentation: str = ""
    source_file: Path | None = None
    line_number: int | None = None


class RobotLibrary(BaseModel):
    name: str
    version: str
    source_path: Path | None = None
    keywords: list[Keyword] = Field(default_factory=list)


class IndexedSymbol(BaseModel):
    id: str
    name: str
    kind: str
    file_path: Path
    line: int = 1
    project_id: UUID | None = None
    workspace_id: UUID | None = None
    documentation: str = ""
    detail: str = ""
    last_modified: float | None = None


class SymbolReference(BaseModel):
    symbol_id: str
    name: str
    file_path: Path
    line: int = 1
    project_id: UUID | None = None
    context: str = ""


class IndexStatus(BaseModel):
    state: str = "idle"
    files_indexed: int = 0
    keywords_indexed: int = 0
    libraries_indexed: int = 0
    variables_indexed: int = 0
    symbols_indexed: int = 0
    last_indexed_at: datetime | None = None
    message: str = ""
    errors: list[str] = Field(default_factory=list)


class ExecutionRun(BaseModel):
    id: UUID
    workspace_id: UUID
    project_id: UUID
    environment_id: UUID
    project_name: str = ""
    suite: str = ""
    status: ExecutionStatus
    started_at: datetime
    finished_at: datetime | None = None
    duration_ms: int | None = None
    exit_code: int | None = None
    command: str = ""
    output_dir: Path | None = None
    output_xml: Path | None = None
    log_html: Path | None = None
    report_html: Path | None = None
    environment_name: str = ""
    robot_version: str | None = None
    total_tests: int | None = None
    passed: int | None = None
    failed: int | None = None
    skipped: int | None = None


class DashboardSummary(BaseModel):
    total_runs: int = 0
    pass_rate: float | None = None
    average_duration_ms: float | None = None
    last_run: ExecutionRun | None = None
    recent_runs: list[ExecutionRun] = Field(default_factory=list)
    recent_failures: list[ExecutionRun] = Field(default_factory=list)


from robot_studio.domain.models.plugin import PluginInfo, PluginManifest, PluginState

