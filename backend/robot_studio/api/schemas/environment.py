from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CreateEnvironmentRequest(BaseModel):
    name: str = Field(min_length=1)
    python_interpreter: str = Field(min_length=1)
    install_robot_framework: bool = False


class ImportEnvironmentRequest(BaseModel):
    path: str = Field(min_length=1)


class ActivateEnvironmentRequest(BaseModel):
    environment_id: UUID


class CloneEnvironmentRequest(BaseModel):
    name: str = Field(min_length=1)


class EnvironmentResponse(BaseModel):
    id: UUID
    workspace_id: UUID
    name: str
    path: str
    python_version: str
    python_executable: str
    pip_executable: str
    robot_executable: str | None = None
    created_at: datetime
    active: bool
    robot_version: str | None = None
    package_count: int = 0
    platform: str | None = None
    architecture: str | None = None
    available: bool = True


class EnvironmentListResponse(BaseModel):
    environments: list[EnvironmentResponse]


class PythonInterpreterResponse(BaseModel):
    path: str
    version: str
    display_name: str


class PythonInterpreterListResponse(BaseModel):
    interpreters: list[PythonInterpreterResponse]
