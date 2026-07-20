from fastapi import APIRouter, Depends, HTTPException

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.plugin import (
    PluginActionRequest,
    PluginListResponse,
    PluginResponse,
    to_plugin_response,
)
from robot_studio.application.services.plugin_service import PluginValidationError

router = APIRouter(prefix="/plugins", tags=["plugins"])


@router.get("", response_model=PluginListResponse)
async def list_plugins(
    gateway: RestGateway = Depends(get_gateway),
) -> PluginListResponse:
    plugins = await gateway.list_plugins()
    return PluginListResponse(plugins=[to_plugin_response(item) for item in plugins])


@router.post("/refresh", response_model=PluginListResponse)
async def refresh_plugins(
    gateway: RestGateway = Depends(get_gateway),
) -> PluginListResponse:
    plugins = await gateway.refresh_plugins()
    return PluginListResponse(plugins=[to_plugin_response(item) for item in plugins])


@router.get("/{plugin_id}", response_model=PluginResponse)
async def get_plugin(
    plugin_id: str,
    gateway: RestGateway = Depends(get_gateway),
) -> PluginResponse:
    plugin = await gateway.get_plugin(plugin_id)
    if plugin is None:
        raise HTTPException(status_code=404, detail=f"Plugin '{plugin_id}' not found")
    return to_plugin_response(plugin)


@router.post("/enable", response_model=PluginResponse)
async def enable_plugin(
    body: PluginActionRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> PluginResponse:
    try:
        plugin = await gateway.enable_plugin(body.id)
    except PluginValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_plugin_response(plugin)


@router.post("/disable", response_model=PluginResponse)
async def disable_plugin(
    body: PluginActionRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> PluginResponse:
    try:
        plugin = await gateway.disable_plugin(body.id)
    except PluginValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_plugin_response(plugin)


@router.post("/reload", response_model=PluginResponse)
async def reload_plugin(
    body: PluginActionRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> PluginResponse:
    try:
        plugin = await gateway.reload_plugin(body.id)
    except PluginValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_plugin_response(plugin)
