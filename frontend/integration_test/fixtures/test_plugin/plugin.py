"""Minimal plugin used by Flutter integration tests."""


class Plugin:
    async def initialize(self, context) -> None:
        return None

    async def activate(self, context) -> None:
        return None

    async def deactivate(self, context) -> None:
        return None

    async def dispose(self, context) -> None:
        return None
