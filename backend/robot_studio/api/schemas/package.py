from uuid import UUID

from pydantic import BaseModel, Field

from robot_studio.domain.models import InstalledPackage, PackageSearchResult


class PackageNameRequest(BaseModel):
    name: str = Field(min_length=1)
    version: str | None = None


class RequirementsFileRequest(BaseModel):
    path: str = Field(min_length=1)


class PackageVersionsResponse(BaseModel):
    name: str
    latest_version: str | None = None
    versions: list[str] = Field(default_factory=list)


class PackageResponse(BaseModel):
    name: str
    version: str
    latest_version: str | None = None
    summary: str | None = None
    author: str | None = None
    homepage: str | None = None
    license: str | None = None
    location: str | None = None
    requires: list[str] = Field(default_factory=list)
    update_available: bool = False


class PackageListResponse(BaseModel):
    packages: list[PackageResponse]
    robot_framework_installed: bool
    robot_framework_version: str | None = None
    environment_id: UUID | None = None
    environment_name: str | None = None


class PackageSearchResponse(BaseModel):
    results: list[PackageSearchResult]


class PackageOperationResponse(BaseModel):
    package: PackageResponse | None = None
    logs: list[str] = Field(default_factory=list)
    robot_framework_installed: bool = False
    robot_framework_version: str | None = None


def to_package_response(package: InstalledPackage) -> PackageResponse:
    return PackageResponse(
        name=package.name,
        version=package.version,
        latest_version=package.latest_version,
        summary=package.summary,
        author=package.author,
        homepage=package.homepage,
        license=package.license,
        location=package.location,
        requires=list(package.requires),
        update_available=package.update_available,
    )
