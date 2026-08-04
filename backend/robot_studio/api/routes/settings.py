"""Application preferences API — SettingsService is the sole owner."""

from fastapi import APIRouter, Depends, HTTPException

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.settings import (
    AppSettingsPatch,
    AppSettingsResponse,
    to_settings_response,
)

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("", response_model=AppSettingsResponse)
async def get_settings(
    gateway: RestGateway = Depends(get_gateway),
) -> AppSettingsResponse:
    return to_settings_response(await gateway.get_settings())


@router.patch("", response_model=AppSettingsResponse)
async def patch_settings(
    body: AppSettingsPatch,
    gateway: RestGateway = Depends(get_gateway),
) -> AppSettingsResponse:
    patch = body.model_dump(exclude_none=True)
    if not patch:
        return to_settings_response(await gateway.get_settings())
    return to_settings_response(await gateway.update_settings(patch))


@router.post("/reset", response_model=AppSettingsResponse)
async def reset_settings(
    gateway: RestGateway = Depends(get_gateway),
) -> AppSettingsResponse:
    try:
        return to_settings_response(await gateway.reset_settings())
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
