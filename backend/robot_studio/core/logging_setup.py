"""Persist Robot Studio backend logs under ``~/.robot-studio/logs``.

Daily files (``backend-YYYY-MM-DD.log``) plus a 7-day purge on startup so
support can collect recent traces without filling the user's disk.
"""

from __future__ import annotations

import logging
import re
import time
from datetime import date, datetime, timedelta
from pathlib import Path

DEFAULT_RETENTION_DAYS = 7
_LOG_NAME_RE = re.compile(r"^(backend|frontend)-(\d{4}-\d{2}-\d{2})\.log$")
_HANDLER_FLAG = "_robot_studio_file_log"
_configured_path: Path | None = None


def logs_dir(data_dir: Path) -> Path:
    return Path(data_dir) / "logs"


def configure_logging(
    data_dir: Path,
    *,
    retention_days: int = DEFAULT_RETENTION_DAYS,
    level: int = logging.INFO,
) -> Path:
    """Attach a daily file handler to the root logger.

    Idempotent for the same day, and **re-attaches** if uvicorn (or anything
    else) replaced root handlers after our first call — otherwise packaged
    Windows builds look like they have empty backend logs.
    """
    global _configured_path
    root = logs_dir(data_dir)
    root.mkdir(parents=True, exist_ok=True)
    purge_old_logs(root, retention_days=retention_days)

    log_path = root / f"backend-{datetime.now().astimezone().date().isoformat()}.log"
    root_logger = logging.getLogger()
    root_logger.setLevel(level)

    if _has_our_handler(root_logger) and _configured_path == log_path:
        return root

    # Drop a stale same-flag handler (e.g. yesterday's path after midnight).
    for handler in list(root_logger.handlers):
        if getattr(handler, _HANDLER_FLAG, False):
            root_logger.removeHandler(handler)
            try:
                handler.close()
            except Exception:  # noqa: BLE001, S110
                pass

    handler = logging.FileHandler(log_path, encoding="utf-8")
    setattr(handler, _HANDLER_FLAG, True)
    handler.setFormatter(
        logging.Formatter(
            fmt="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        ),
    )
    handler.setLevel(level)
    root_logger.addHandler(handler)

    # Keep uvicorn/access noise at INFO; don't force DEBUG onto disk.
    logging.getLogger("uvicorn.access").setLevel(logging.INFO)
    logging.getLogger("uvicorn.error").setLevel(logging.INFO)
    # Ensure access lines reach our root file handler.
    logging.getLogger("uvicorn.access").propagate = True
    logging.getLogger("uvicorn.error").propagate = True

    _configured_path = log_path
    logging.getLogger(__name__).info("Backend file logging → %s", log_path)
    return root


def ensure_file_logging(data_dir: Path) -> Path:
    """Re-assert the file handler after uvicorn may have reconfigured logging."""
    return configure_logging(data_dir)


def _has_our_handler(logger: logging.Logger) -> bool:
    return any(getattr(h, _HANDLER_FLAG, False) for h in logger.handlers)


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
    today = datetime.fromtimestamp(clock).astimezone().date()
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
                stamped = datetime.fromtimestamp(path.stat().st_mtime).astimezone().date()
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
    if match is None:
        return None
    try:
        year, month, day = (int(part) for part in match.group(2).split("-"))
        return date(year, month, day)
    except ValueError:
        return None


def _reset_for_tests() -> None:
    """Drop the idempotency latch so unit tests can reconfigure."""
    global _configured_path
    _configured_path = None
    root = logging.getLogger()
    for handler in list(root.handlers):
        if getattr(handler, _HANDLER_FLAG, False):
            root.removeHandler(handler)
            try:
                handler.close()
            except Exception:  # noqa: BLE001, S110
                pass
