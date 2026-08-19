"""Shared subprocess helpers — especially Windows GUI / frozen-sidecar safety."""

from __future__ import annotations

import asyncio
import os
import subprocess
import sys
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from typing import TypeVar

_T = TypeVar("_T")

_blocking_pool: ThreadPoolExecutor | None = None


def init_blocking_pool(*, loop: asyncio.AbstractEventLoop | None = None) -> None:
    """Reserve worker threads for git / Python probes / watchdog attach.

    The default asyncio pool is small (≈6 on a 2-core VM). Indexing plus open-
    project git/env probes can queue behind each other; a larger dedicated pool
    keeps health checks and lightweight handlers responsive on Windows sidecars.
    """
    global _blocking_pool
    if _blocking_pool is not None:
        return
    workers = 32 if sys.platform == "win32" else max(16, (os.cpu_count() or 4) * 2)
    _blocking_pool = ThreadPoolExecutor(
        max_workers=workers,
        thread_name_prefix="robot-studio-blocking",
    )
    target_loop = loop or asyncio.get_running_loop()
    target_loop.set_default_executor(_blocking_pool)


def shutdown_blocking_pool() -> None:
    global _blocking_pool
    if _blocking_pool is None:
        return
    _blocking_pool.shutdown(wait=False, cancel_futures=True)
    _blocking_pool = None


async def run_blocking(func: Callable[..., _T], /, *args, **kwargs) -> _T:
    """Run sync work (subprocess, watchdog schedule, …) off the event loop."""
    loop = asyncio.get_running_loop()
    pool = _blocking_pool
    if pool is None:
        if kwargs:
            return await asyncio.to_thread(lambda: func(*args, **kwargs))
        return await asyncio.to_thread(func, *args)
    if kwargs:
        return await loop.run_in_executor(
            pool,
            lambda: func(*args, **kwargs),
        )
    return await loop.run_in_executor(pool, func, *args)


def windows_no_window_kwargs() -> dict:
    """Avoid console allocation hangs when spawning from a GUI / frozen app.

    On Windows, starting a console subsystem binary (git, python, …) from a
    process without a console can block inside CreateProcess for a long time
    unless ``CREATE_NO_WINDOW`` is set. That freeze runs on the asyncio thread
    and stalls every HTTP request (30s client timeouts).
    """
    if sys.platform != "win32":
        return {}
    return {"creationflags": getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)}
