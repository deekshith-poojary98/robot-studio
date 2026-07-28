from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from robot_studio.api.schemas.workspace import WorkspaceResponse
from robot_studio.domain.models import ProjectType


class CreateProjectRequest(BaseModel):
    name: str = Field(min_length=1)


class ImportProjectRequest(BaseModel):
    path: str = Field(min_length=1)


class OpenProjectRequest(BaseModel):
    project_id: UUID


class OpenProjectByPathRequest(BaseModel):
    path: str = Field(min_length=1)
    force: bool = False


class CreateStandaloneProjectRequest(BaseModel):
    name: str = Field(min_length=1)
    location: str = Field(min_length=1)


class DetectedEnvironment(BaseModel):
    name: str
    path: str


class ProjectResponse(BaseModel):
    id: UUID
    workspace_id: UUID
    name: str
    path: str
    type: ProjectType
    created_at: datetime


class ProjectListResponse(BaseModel):
    projects: list[ProjectResponse]


class OpenProjectByPathResponse(BaseModel):
    workspace: WorkspaceResponse
    project: ProjectResponse
    needs_environment: bool = False
    detected_environments: list[DetectedEnvironment] = Field(default_factory=list)
