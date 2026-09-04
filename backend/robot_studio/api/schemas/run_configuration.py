from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field
from robot_studio.domain.models.run_configuration import RunConfiguration, RunVariable


class RunVariablePayload(BaseModel):
    key: str
    value: str = ""


class RunConfigurationResponse(BaseModel):
    id: UUID
    name: str
    environment_id: UUID | None = None
    include_tags: list[str] = Field(default_factory=list)
    exclude_tags: list[str] = Field(default_factory=list)
    variables: list[RunVariablePayload] = Field(default_factory=list)
    variable_files: list[str] = Field(default_factory=list)
    extra_robot_args: list[str] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_model(cls, item: RunConfiguration) -> RunConfigurationResponse:
        return cls(
            id=item.id,
            name=item.name,
            environment_id=item.environment_id,
            include_tags=list(item.include_tags),
            exclude_tags=list(item.exclude_tags),
            variables=[
                RunVariablePayload(key=row.key, value=row.value) for row in item.variables
            ],
            variable_files=list(item.variable_files),
            extra_robot_args=list(item.extra_robot_args),
            created_at=item.created_at,
            updated_at=item.updated_at,
        )


class RunConfigurationListResponse(BaseModel):
    active_id: UUID | None = None
    configurations: list[RunConfigurationResponse] = Field(default_factory=list)


class RunConfigurationWriteRequest(BaseModel):
    name: str
    environment_id: UUID | None = None
    include_tags: list[str] = Field(default_factory=list)
    exclude_tags: list[str] = Field(default_factory=list)
    variables: list[RunVariablePayload] = Field(default_factory=list)
    variable_files: list[str] = Field(default_factory=list)
    extra_robot_args: list[str] = Field(default_factory=list)
    activate: bool = True


class RunConfigurationPatchRequest(BaseModel):
    name: str | None = None
    environment_id: UUID | None = None
    clear_environment: bool = False
    include_tags: list[str] | None = None
    exclude_tags: list[str] | None = None
    variables: list[RunVariablePayload] | None = None
    variable_files: list[str] | None = None
    extra_robot_args: list[str] | None = None


class ActivateRunConfigurationRequest(BaseModel):
    configuration_id: UUID | None = None


def to_variables(rows: list[RunVariablePayload] | None) -> list[RunVariable] | None:
    if rows is None:
        return None
    return [RunVariable(key=row.key, value=row.value) for row in rows]
