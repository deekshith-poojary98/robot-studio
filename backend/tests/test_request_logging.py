"""Tests for HTTP request logging middleware."""

from __future__ import annotations

import logging
from pathlib import Path
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.core.config import settings
from robot_studio.core.container import Container
from robot_studio.core.request_logging import REQUEST_ID_HEADER, is_quiet_path
from robot_studio.main import create_app


def test_is_quiet_path() -> None:
    assert is_quiet_path("/api/v1/health")
    assert is_quiet_path("/health")
    assert not is_quiet_path("/api/v1/insights")
    assert not is_quiet_path("/api/v1/execution/status")


@pytest.fixture
async def api_client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "data_dir", tmp_path / "data")
    settings.data_dir.mkdir(parents=True, exist_ok=True)

    fresh = Container()
    await fresh.initialize_async()

    app = create_app()
    app.dependency_overrides[get_gateway] = lambda: RestGateway(fresh)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        try:
            yield client, fresh, tmp_path
        finally:
            await fresh.shutdown()
    app.dependency_overrides.clear()


async def test_request_logging_emits_line_and_header(
    api_client,
    caplog: pytest.LogCaptureFixture,
) -> None:
    client, _fresh, _tmp = api_client
    with caplog.at_level(logging.INFO, logger="robot_studio.request"):
        response = await client.get("/api/v1/settings")

    assert response.status_code == 200
    assert REQUEST_ID_HEADER in response.headers
    assert response.headers[REQUEST_ID_HEADER]
    assert any(
        "GET /api/v1/settings → 200" in record.getMessage()
        and "req=" in record.getMessage()
        for record in caplog.records
    )


async def test_health_is_not_logged(
    api_client,
    caplog: pytest.LogCaptureFixture,
) -> None:
    client, _fresh, _tmp = api_client
    with caplog.at_level(logging.INFO, logger="robot_studio.request"):
        response = await client.get("/api/v1/health")

    assert response.status_code == 200
    assert not any("/health" in record.getMessage() for record in caplog.records)


async def test_propagates_incoming_request_id(api_client) -> None:
    client, _fresh, _tmp = api_client
    response = await client.get(
        "/api/v1/settings",
        headers={REQUEST_ID_HEADER: "client-req-1"},
    )
    assert response.headers[REQUEST_ID_HEADER] == "client-req-1"


async def test_http_errors_still_return_status(api_client) -> None:
    """Exception handler must not turn 404/400 into opaque 500s."""
    client, _fresh, _tmp = api_client
    response = await client.get(f"/api/v1/reports/{uuid4()}")
    assert response.status_code in {400, 404}
