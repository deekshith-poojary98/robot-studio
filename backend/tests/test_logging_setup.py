"""Tests for local file logging + weekly retention."""

from __future__ import annotations

import logging
import time
from datetime import datetime, timedelta
from pathlib import Path

from robot_studio.core import logging_setup


def test_purge_old_logs_keeps_week_and_deletes_older(tmp_path: Path) -> None:
    logs = tmp_path / "logs"
    logs.mkdir()
    today = datetime.now().astimezone().date()
    keep = logs / f"backend-{today.isoformat()}.log"
    keep.write_text("fresh\n", encoding="utf-8")
    mid = logs / f"frontend-{(today - timedelta(days=3)).isoformat()}.log"
    mid.write_text("mid\n", encoding="utf-8")
    stale = logs / f"backend-{(today - timedelta(days=8)).isoformat()}.log"
    stale.write_text("old\n", encoding="utf-8")
    unrelated = logs / "notes.txt"
    unrelated.write_text("leave me\n", encoding="utf-8")

    deleted = logging_setup.purge_old_logs(logs, retention_days=7)

    assert stale in deleted
    assert not stale.exists()
    assert keep.exists()
    assert mid.exists()
    assert unrelated.exists()


def test_purge_falls_back_to_mtime_for_unstamped_names(tmp_path: Path) -> None:
    logs = tmp_path / "logs"
    logs.mkdir()
    old = logs / "sidecar.log"
    old.write_text("old\n", encoding="utf-8")
    # Age the file beyond the retention window (10 calendar days ago).
    past = time.time() - (10 * 86_400)
    import os

    os.utime(old, (past, past))

    deleted = logging_setup.purge_old_logs(logs, retention_days=7, now=time.time())

    assert deleted == [old]
    assert not old.exists()


def test_purge_keeps_file_on_the_retention_boundary(tmp_path: Path) -> None:
    logs = tmp_path / "logs"
    logs.mkdir()
    today = datetime.now().astimezone().date()
    boundary = logs / f"frontend-{(today - timedelta(days=7)).isoformat()}.log"
    boundary.write_text("edge\n", encoding="utf-8")

    deleted = logging_setup.purge_old_logs(logs, retention_days=7)

    assert deleted == []
    assert boundary.exists()


def test_configure_logging_writes_daily_file(tmp_path: Path) -> None:
    logging_setup._reset_for_tests()
    # Drop leftover file handlers from other tests / prior runs.
    root_logger = logging.getLogger()
    for handler in list(root_logger.handlers):
        if isinstance(handler, logging.FileHandler):
            root_logger.removeHandler(handler)
            handler.close()

    try:
        root = logging_setup.configure_logging(tmp_path, retention_days=7)
        assert root == tmp_path / "logs"
        expected = root / f"backend-{datetime.now().astimezone().date().isoformat()}.log"
        assert expected.is_file()

        logging.getLogger("robot_studio.test").info("hello from test")
        for handler in root_logger.handlers:
            handler.flush()

        contents = expected.read_text(encoding="utf-8")
        assert "hello from test" in contents
        assert "Backend file logging" in contents
    finally:
        for handler in list(root_logger.handlers):
            if isinstance(handler, logging.FileHandler):
                root_logger.removeHandler(handler)
                handler.close()
        logging_setup._reset_for_tests()
