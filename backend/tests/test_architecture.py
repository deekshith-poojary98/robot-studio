"""Structural tests for v2 architecture components."""

from uuid import uuid4

import pytest

from robot_studio.api.gateway import RestGateway
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.container import Container
from robot_studio.core.events import (
    InMemoryEventBus,
    WorkspaceClosed,
    WorkspaceOpened,
)
from robot_studio.core.plugins import PluginHost, REGISTERED_MODULES
from robot_studio.domain.interfaces.plugins import Capability
from robot_studio.domain.models import Workspace
from robot_studio.infrastructure.plugins.builtins import register_builtin_capabilities


@pytest.fixture
async def container():
    c = Container()
    c.initialize()
    try:
        yield c
    finally:
        await c.shutdown()


@pytest.mark.asyncio
async def test_event_bus_publish_subscribe() -> None:
    bus = InMemoryEventBus()
    received: list[WorkspaceOpened] = []

    async def handler(event: WorkspaceOpened) -> None:
        received.append(event)

    workspace_id = uuid4()
    bus.subscribe(WorkspaceOpened, handler)
    await bus.publish(WorkspaceOpened(workspace_id=workspace_id))

    assert len(received) == 1
    assert received[0].workspace_id == workspace_id


@pytest.mark.asyncio
async def test_workspace_context_open_close(container: Container) -> None:
    assert container.workspace_context is not None
    ctx = container.workspace_context
    events: list[str] = []

    async def on_open(_: WorkspaceOpened) -> None:
        events.append("opened")

    async def on_close(_: WorkspaceClosed) -> None:
        events.append("closed")

    container.event_bus.subscribe(WorkspaceOpened, on_open)
    container.event_bus.subscribe(WorkspaceClosed, on_close)

    workspace = Workspace(
        id=uuid4(),
        name="Test",
        path="/tmp/test",
        created_at=__import__("datetime").datetime.now(__import__("datetime").UTC),
    )

    await ctx.open(workspace)
    assert ctx.is_open
    assert ctx.workspace_id == workspace.id

    await ctx.close()
    assert not ctx.is_open
    assert events == ["opened", "closed"]


def test_plugin_host_registers_builtins() -> None:
    host = PluginHost()
    register_builtin_capabilities(host)

    assert host.get_provider_id(Capability.RUNNER) == "robot-cli-runner"
    assert host.get_provider_id(Capability.INSTALLER) == "pip-installer"
    assert host.list_modules() == REGISTERED_MODULES
    assert not host.has(Capability.RUNNER)


@pytest.mark.asyncio
async def test_rest_gateway_health(container: Container) -> None:
    gateway = RestGateway(container)
    response = await gateway.health()

    assert response.status == "ok"
    assert response.version == "0.1.0"
    assert response.modules == REGISTERED_MODULES


@pytest.mark.asyncio
async def test_health_api_unchanged(container: Container) -> None:
    from httpx import ASGITransport, AsyncClient

    from robot_studio.main import create_app

    app = create_app()
    transport = ASGITransport(app=app)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "version": "0.1.0",
        "modules": REGISTERED_MODULES,
    }
