"""Shared pytest fixtures.

Tests use PollingFileWatcher instead of watchdog so suite teardown cannot
livelock on observer threads that keep arming asyncio callbacks.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from robot_studio.infrastructure.indexing.file_watcher import PollingFileWatcher


@pytest.fixture(autouse=True)
def _use_polling_file_watcher(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "robot_studio.core.container.NativeFileWatcher",
        PollingFileWatcher,
    )


@pytest.fixture(autouse=True)
def _restore_process_cwd() -> None:
    """Put the working directory back after every test.

    The cwd is process-global: a test that chdirs into a directory it then
    deletes leaves every later `subprocess.run` without an explicit ``cwd``
    failing in ``os.getcwd()``/``abspath``, far away from the real cause.
    """
    try:
        original: str | None = os.getcwd()
    except OSError:  # Already destroyed by an earlier leak.
        original = None
    yield
    if original is None or not Path(original).is_dir():
        return
    try:
        if os.getcwd() != original:
            os.chdir(original)
    except OSError:
        os.chdir(original)
