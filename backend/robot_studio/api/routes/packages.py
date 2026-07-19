from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.package import (
    PackageListResponse,
    PackageNameRequest,
    PackageOperationResponse,
    PackageResponse,
    PackageSearchResponse,
    PackageVersionsResponse,
    to_package_response,
)
from robot_studio.application.services.package_service import PackageValidationError

router = APIRouter(prefix="/packages", tags=["packages"])


@router.get("", response_model=PackageListResponse)
async def list_packages(
    q: str | None = Query(default=None),
    sort: str = Query(default="name"),
    gateway: RestGateway = Depends(get_gateway),
) -> PackageListResponse:
    try:
        result = await gateway.list_packages(query=q, sort=sort)
    except PackageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return PackageListResponse(
        packages=[to_package_response(item) for item in result.packages],
        robot_framework_installed=result.robot_framework_installed,
        robot_framework_version=result.robot_framework_version,
        environment_id=result.environment.id,
        environment_name=result.environment.name,
    )


@router.get("/search", response_model=PackageSearchResponse)
async def search_packages(
    q: str = Query(min_length=1),
    gateway: RestGateway = Depends(get_gateway),
) -> PackageSearchResponse:
    try:
        results = await gateway.search_packages(query=q)
    except PackageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return PackageSearchResponse(results=results)


@router.get("/{name}/versions", response_model=PackageVersionsResponse)
async def list_package_versions(
    name: str,
    gateway: RestGateway = Depends(get_gateway),
) -> PackageVersionsResponse:
    try:
        versions = await gateway.list_package_versions(name=name)
    except PackageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    latest = versions[0] if versions else None
    return PackageVersionsResponse(
        name=name,
        latest_version=latest,
        versions=versions,
    )


@router.post("/install", response_model=PackageOperationResponse)
async def install_package(
    request: PackageNameRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> PackageOperationResponse:
    try:
        result = await gateway.install_package(
            name=request.name,
            version=request.version,
        )
    except PackageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return PackageOperationResponse(
        package=to_package_response(result.package) if result.package else None,
        logs=result.logs,
        robot_framework_installed=result.robot_framework_installed,
        robot_framework_version=result.robot_framework_version,
    )


@router.post("/update", response_model=PackageOperationResponse)
async def update_package(
    request: PackageNameRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> PackageOperationResponse:
    try:
        result = await gateway.update_package(name=request.name)
    except PackageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return PackageOperationResponse(
        package=to_package_response(result.package) if result.package else None,
        logs=result.logs,
        robot_framework_installed=result.robot_framework_installed,
        robot_framework_version=result.robot_framework_version,
    )


@router.post("/uninstall", response_model=PackageOperationResponse)
async def uninstall_package(
    request: PackageNameRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> PackageOperationResponse:
    try:
        result = await gateway.uninstall_package(name=request.name)
    except PackageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return PackageOperationResponse(
        package=None,
        logs=result.logs,
        robot_framework_installed=result.robot_framework_installed,
        robot_framework_version=result.robot_framework_version,
    )


@router.get("/{name}", response_model=PackageResponse)
async def get_package(
    name: str,
    gateway: RestGateway = Depends(get_gateway),
) -> PackageResponse:
    try:
        package = await gateway.get_package(name=name)
    except PackageValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_package_response(package)
