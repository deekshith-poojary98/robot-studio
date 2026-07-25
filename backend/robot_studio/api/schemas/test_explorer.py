"""Schemas for Test Explorer API."""

from __future__ import annotations

from pydantic import BaseModel, Field


class TestNodeResponse(BaseModel):
    id: str
    kind: str
    name: str
    path: str | None = None
    line: int | None = None
    project_id: str | None = None
    status: str = "not_run"
    tags: list[str] = Field(default_factory=list)
    detail: str = ""
    children: list[TestNodeResponse] = Field(default_factory=list)


class TestTreeResponse(BaseModel):
    tree: TestNodeResponse


class TestFileResponse(BaseModel):
    nodes: list[TestNodeResponse]


class RunTestRequest(BaseModel):
    file: str = Field(min_length=1)
    name: str = Field(min_length=1)


class RunSuiteRequest(BaseModel):
    file: str | None = None


class RunTagRequest(BaseModel):
    tag: str = Field(min_length=1)


class RunSelectedTest(BaseModel):
    file: str = Field(min_length=1)
    name: str = Field(min_length=1)


class RunSelectedRequest(BaseModel):
    tests: list[RunSelectedTest] = Field(min_length=1)


def to_test_node(node) -> TestNodeResponse:
    return TestNodeResponse.model_validate(node.to_dict())
