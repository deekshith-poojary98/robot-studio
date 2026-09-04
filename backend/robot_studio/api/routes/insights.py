"""Project Insights REST — /insights."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.insights import InsightsResponse, to_insights_response
from robot_studio.application.services.insights_service import InsightsValidationError

router = APIRouter(prefix="/insights", tags=["insights"])
GatewayDep = Annotated[RestGateway, Depends(get_gateway)]


@router.get("", response_model=InsightsResponse)
async def get_insights(
    gateway: GatewayDep,
) -> InsightsResponse:
    try:
        snapshot = await gateway.get_insights()
    except InsightsValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_insights_response(snapshot)
