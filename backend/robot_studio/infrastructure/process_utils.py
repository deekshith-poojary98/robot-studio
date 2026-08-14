"""Shared subprocess helpers — especially Windows GUI / frozen-sidecar safety."""

from __future__ import annotations

import subprocess
import sys


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
