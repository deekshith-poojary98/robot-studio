"""Named Robot execution contexts persisted with the project."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class RunVariable(BaseModel):
    """One Robot ``--variable KEY:value`` pair."""

    key: str
    value: str = ""


class RunConfiguration(BaseModel):
    id: UUID
    name: str
    environment_id: UUID | None = None
    include_tags: list[str] = Field(default_factory=list)
    exclude_tags: list[str] = Field(default_factory=list)
    variables: list[RunVariable] = Field(default_factory=list)
    variable_files: list[str] = Field(default_factory=list)
    extra_robot_args: list[str] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class RunConfigurationStore(BaseModel):
    version: int = 1
    active_id: UUID | None = None
    configurations: list[RunConfiguration] = Field(default_factory=list)
