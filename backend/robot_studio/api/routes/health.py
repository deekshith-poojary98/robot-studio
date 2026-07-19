from fastapi import APIRouter, Depends

from robot_studio.api.gateway import RestGateway
from robot_studio.api.schemas.health import HealthResponse
from robot_studio.core.container import container


def get_gateway() -> RestGateway:
    return RestGateway(container)


router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
async def health(gateway: RestGateway = Depends(get_gateway)) -> HealthResponse:
    return await gateway.health()
