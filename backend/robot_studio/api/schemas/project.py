from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from robot_studio.domain.models import ProjectType


class CreateProjectRequest(BaseModel):
    name: str = Field(min_length=1)
    type: ProjectType


class ImportProjectRequest(BaseModel):
    path: str = Field(min_length=1)


class OpenProjectRequest(BaseModel):
    project_id: UUID


class ProjectResponse(BaseModel):
    id: UUID
    workspace_id: UUID
    name: str
    path: str
    type: ProjectType
    created_at: datetime


class ProjectListResponse(BaseModel):
    projects: list[ProjectResponse]
