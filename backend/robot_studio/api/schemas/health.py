from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: str
    version: str
    modules: list[str]
