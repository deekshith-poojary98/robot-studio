from datetime import datetime

from pydantic import BaseModel, Field


class PluginResponse(BaseModel):
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


class PluginListResponse(BaseModel):
    plugins: list[PluginResponse] = Field(default_factory=list)


class PluginActionRequest(BaseModel):
    id: str


def to_plugin_response(item) -> PluginResponse:
    return PluginResponse(
        id=item.id,
        name=item.name,
        version=item.version,
        author=item.author,
        description=item.description,
        status=item.status,
        enabled=item.enabled,
        capabilities=item.capabilities,
        path=item.path,
        is_builtin=item.is_builtin,
        error=item.error,
        loaded_at=item.loaded_at,
    )
