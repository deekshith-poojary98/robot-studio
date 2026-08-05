"""Persist Robot Studio backend logs under ``~/.robot-studio/logs``.

Daily files (``backend-YYYY-MM-DD.log``) plus a 7-day purge on startup so
support can collect recent traces without filling the user's disk.
"""

from __future__ import annotations

import logging
import re
import time
from datetime import date, timedelta
from pathlib import Path

DEFAULT_RETENTION_DAYS = 7
_LOG_NAME_RE = re.compile(r"^(backend|frontend)-(\d{4}-\d{2}-\d{2})\.log$")
_configured = False


def logs_dir(data_dir: Path) -> Path:
    return Path(data_dir) / "logs"


def configure_logging(
    data_dir: Path,
    *,
    retention_days: int = DEFAULT_RETENTION_DAYS,
    level: int = logging.INFO,
) -> Path:
    """Attach a daily file handler to the root logger (idempotent)."""
    global _configured
    root = logs_dir(data_dir)
    root.mkdir(parents=True, exist_ok=True)
    purge_old_logs(root, retention_days=retention_days)

    if _configured:
        return root

    log_path = root / f"backend-{date.today().isoformat()}.log"
    handler = logging.FileHandler(log_path, encoding="utf-8")
    handler.setFormatter(
        logging.Formatter(
            fmt="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        ),
    )
    handler.setLevel(level)

    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    root_logger.addHandler(handler)

    # Keep uvicorn/access noise at INFO; don't force DEBUG onto disk.
    logging.getLogger("uvicorn.access").setLevel(logging.INFO)
    logging.getLogger("uvicorn.error").setLevel(logging.INFO)

    _configured = True
    logging.getLogger(__name__).info("Backend file logging → %s", log_path)
    return root


def purge_old_logs(
    directory: Path,
    *,
    retention_days: int = DEFAULT_RETENTION_DAYS,
    now: float | None = None,
) -> list[Path]:
    """Delete ``backend-`` / ``frontend-`` daily logs older than [retention_days].

    Prefers the date stamped in the filename; falls back to mtime. A file
    dated exactly ``today - retention_days`` is kept. Returns deleted paths.
    """
    days = max(1, retention_days)
    clock = now if now is not None else time.time()
    today = date.fromtimestamp(clock)
    cutoff = today - timedelta(days=days)
    deleted: list[Path] = []
    if not directory.is_dir():
        return deleted

    for path in directory.iterdir():
        if not path.is_file() or path.suffix != ".log":
            continue
        stamped = _file_date(path)
        if stamped is None:
            try:
                stamped = date.fromtimestamp(path.stat().st_mtime)
            except OSError:
                continue
        if stamped >= cutoff:
            continue
        try:
            path.unlink()
            deleted.append(path)
        except OSError:
            continue
    return deleted


def _file_date(path: Path) -> date | None:
    match = _LOG_NAME_RE.match(path.name)
    if not match:
        return None
    try:
        year, month, day = (int(part) for part in match.group(2).split("-"))
        return date(year, month, day)
    except ValueError:
        return None


def _reset_for_tests() -> None:
    """Drop the idempotency latch so unit tests can reconfigure."""
    global _configured
    _configured = False
