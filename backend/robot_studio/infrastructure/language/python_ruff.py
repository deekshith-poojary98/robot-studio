"""Run ``ruff check`` from the active environment when it is installed.

Ruff is not bundled. When the project's interpreter has it, its findings
replace pyflakes so Problems matches the same F/E rules CI uses. When ruff is
absent, callers keep using pyflakes.
"""

from __future__ import annotations

import json
import logging
import subprocess
from pathlib import Path
from typing import Any

from robot_studio.infrastructure.process_utils import windows_no_window_kwargs

logger = logging.getLogger(__name__)

_TIMEOUT_SECONDS = 20
_ERROR_PREFIXES = ("E9", "F8", "invalid")


def ruff_check_diagnostics(
    content: str,
    file_path: str,
    python_executable: Path,
) -> list[dict[str, Any]] | None:
    """Ruff findings, ``[]`` if clean, or ``None`` when ruff is unavailable."""
    if not content.strip():
        return None

    target = file_path or "buffer.py"
    args = [
        str(python_executable),
        "-m",
        "ruff",
        "check",
        "--output-format",
        "json",
        "--stdin-filename",
        target,
        "-",
    ]
    try:
        result = subprocess.run(  # noqa: S603 — fixed argv, interpreter from env
            args,
            input=content,
            capture_output=True,
            text=True,
            timeout=_TIMEOUT_SECONDS,
            **windows_no_window_kwargs(),
        )
    except (OSError, subprocess.TimeoutExpired):
        logger.debug("ruff check unavailable for %s", target, exc_info=True)
        return None

    if result.returncode == 0:
        raw = (result.stdout or "").strip()
        if not raw:
            return []
        return _parse_ruff_json(raw, target)
    if result.returncode == 1:
        raw = (result.stdout or "").strip()
        # ``python -m ruff`` also exits 1 when the module is missing; that
        # writes the traceback to stderr and leaves stdout empty.
        if not raw:
            logger.debug(
                "ruff check unavailable for %s: %s",
                target,
                (result.stderr or "").strip()[:200],
            )
            return None
        return _parse_ruff_json(raw, target)

    logger.debug(
        "ruff check exited %s for %s: %s",
        result.returncode,
        target,
        (result.stderr or "").strip()[:200],
    )
    return None


def _parse_ruff_json(raw: str, target: str) -> list[dict[str, Any]] | None:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        logger.debug("ruff check returned non-JSON for %s", target)
        return None
    if not isinstance(payload, list):
        return []
    out: list[dict[str, Any]] = []
    for item in payload:
        if not isinstance(item, dict):
            continue
        code = str(item.get("code") or "")
        message = str(item.get("message") or code or "ruff")
        location = item.get("location") if isinstance(item.get("location"), dict) else {}
        line = int(location.get("row") or 1)
        column = int(location.get("column") or 1)
        severity = "error" if any(code.startswith(p) for p in _ERROR_PREFIXES) else "warning"
        out.append(
            {
                "line": line,
                "column": max(column, 1),
                "end_line": line,
                "end_column": max(column, 1),
                "message": message if not code else f"{code}: {message}",
                "severity": severity,
                "code": code or "ruff",
                "source": "ruff",
            },
        )
    return out
