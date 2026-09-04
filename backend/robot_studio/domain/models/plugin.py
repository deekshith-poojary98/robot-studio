"""Plugin domain models."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from pydantic import BaseModel, Field, field_validator
from robot_studio.domain.interfaces.plugins import Capability, capability_from_manifest


class PluginManifest(BaseModel):
    id: str = Field(min_length=1)
    name: str = Field(min_length=1)
    version: str = Field(min_length=1)
    author: str = ""
    description: str = ""
    entry: str = "plugin.py"
    capabilities: list[str] = Field(default_factory=list)

    @field_validator("id")
    @classmethod
    def validate_id(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned.replace("-", "").replace("_", "").isalnum():
            raise ValueError("Plugin id must be alphanumeric with dashes or underscores")
        return cleaned

    @field_validator("capabilities", mode="before")
    @classmethod
    def normalize_capabilities(cls, value: Any) -> list[str]:
        if value is None:
            return []
        if isinstance(value, str):
            return [value]
        return [str(item) for item in value]

    def resolved_capabilities(self) -> list[Capability]:
        resolved: list[Capability] = []
        for item in self.capabilities:
            capability = capability_from_manifest(item)
            if capability is not None:
                resolved.append(capability)
        return resolved


class PluginState(BaseModel):
    id: str
    enabled: bool = True
    loaded_at: datetime | None = None
    error: str | None = None


class PluginInfo(BaseModel):
    id: str
    name: str
    version: str
    author: str = ""
    description: str = ""
    status: str
    enabled: bool
    capabilities: list[str] = Field(default_factory=list)
    path: str | None = None
    is_builtin: bool = False
    error: str | None = None
    loaded_at: datetime | None = None

    @classmethod
    def from_record(
        cls,
        manifest: PluginManifest,
        *,
        status: str,
        enabled: bool,
        path: str | None,
        is_builtin: bool,
        error: str | None = None,
        loaded_at: datetime | None = None,
    ) -> PluginInfo:
        return cls(
            id=manifest.id,
            name=manifest.name,
            version=manifest.version,
            author=manifest.author,
            description=manifest.description,
            status=status,
            enabled=enabled,
            capabilities=manifest.capabilities,
            path=path,
            is_builtin=is_builtin,
            error=error,
            loaded_at=loaded_at,
        )


def utc_now() -> datetime:
    return datetime.now(UTC)
