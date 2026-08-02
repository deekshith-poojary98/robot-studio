from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from robot_studio.domain.models import ExecutionRun, ExecutionStatus


class RunFileRequest(BaseModel):
    file: str | None = None
    confirm: bool = False


class RunProjectRequest(BaseModel):
    confirm: bool = False


class ExecutionResponse(BaseModel):
    id: UUID
    workspace_id: UUID
    project_id: UUID
    environment_id: UUID
    project_name: str
    suite: str
    status: ExecutionStatus
    started_at: datetime
    finished_at: datetime | None = None
    duration_ms: int | None = None
    exit_code: int | None = None
    command: str = ""
    output_dir: str | None = None
    output_xml: str | None = None
    log_html: str | None = None
    report_html: str | None = None
    environment_name: str = ""
    robot_version: str | None = None
    total_tests: int | None = None
    passed: int | None = None
    failed: int | None = None
    skipped: int | None = None


class ExecutionHistoryResponse(BaseModel):
    runs: list[ExecutionResponse] = Field(default_factory=list)


class ExecutionStatusResponse(BaseModel):
    status: ExecutionStatus
    run: ExecutionResponse | None = None


def to_execution_response(run: ExecutionRun) -> ExecutionResponse:
    return ExecutionResponse(
        id=run.id,
        workspace_id=run.workspace_id,
        project_id=run.project_id,
        environment_id=run.environment_id,
        project_name=run.project_name,
        suite=run.suite,
        status=run.status,
        started_at=run.started_at,
        finished_at=run.finished_at,
        duration_ms=run.duration_ms,
        exit_code=run.exit_code,
        command=run.command,
        output_dir=str(run.output_dir) if run.output_dir else None,
        output_xml=str(run.output_xml) if run.output_xml else None,
        log_html=str(run.log_html) if run.log_html else None,
        report_html=str(run.report_html) if run.report_html else None,
        environment_name=run.environment_name,
        robot_version=run.robot_version,
        total_tests=run.total_tests,
        passed=run.passed,
        failed=run.failed,
        skipped=run.skipped,
    )
