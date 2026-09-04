from typing import Annotated

from fastapi import APIRouter, Depends
from robot_studio.api.gateway import RestGateway
from robot_studio.api.schemas.health import HealthResponse
from robot_studio.core.container import container


def get_gateway() -> RestGateway:
    return RestGateway(container)


router = APIRouter(tags=["health"])
GatewayDep = Annotated[RestGateway, Depends(get_gateway)]


@router.get("/health", response_model=HealthResponse)
async def health(gateway: GatewayDep) -> HealthResponse:
    return await gateway.health()
