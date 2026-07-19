from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CreateWorkspaceRequest(BaseModel):
    name: str = Field(min_length=1)
    location: str = Field(min_length=1)


class OpenWorkspaceRequest(BaseModel):
    path: str = Field(min_length=1)


class WorkspaceResponse(BaseModel):
    id: UUID
    name: str
    path: str
    created_at: datetime


class RecentWorkspacesResponse(BaseModel):
    workspaces: list[WorkspaceResponse]
