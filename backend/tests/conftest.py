"""Shared pytest fixtures.

Tests use PollingFileWatcher instead of watchdog so suite teardown cannot
livelock on observer threads that keep arming asyncio callbacks.
"""

from __future__ import annotations

import pytest

from robot_studio.infrastructure.indexing.file_watcher import PollingFileWatcher


@pytest.fixture(autouse=True)
def _use_polling_file_watcher(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "robot_studio.core.container.NativeFileWatcher",
        PollingFileWatcher,
    )
