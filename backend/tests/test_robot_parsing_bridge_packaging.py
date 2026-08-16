"""Tests for packaged parsing-worker path resolution."""

from __future__ import annotations

from pathlib import Path

import pytest

import robot_studio.infrastructure.language.robot_parsing_bridge as bridge
from robot_studio.infrastructure.language.robot_parsing_bridge import (
    RobotParsingError,
    _robot_parsing_worker_source,
)


def test_parsing_worker_source_resolves_in_dev_tree() -> None:
    worker = _robot_parsing_worker_source()
    assert worker.is_file()
    assert worker.name == "robot_parsing_worker.py"


def test_parsing_worker_source_uses_meipass(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    bundled = (
        tmp_path
        / "robot_studio"
        / "infrastructure"
        / "language"
        / "robot_parsing_worker.py"
    )
    bundled.parent.mkdir(parents=True)
    bundled.write_text("# worker\n", encoding="utf-8")

    missing_dir = tmp_path / "missing"
    missing_dir.mkdir()
    monkeypatch.setattr(
        bridge,
        "__file__",
        str(missing_dir / "robot_parsing_bridge.py"),
    )
    monkeypatch.setattr(bridge.sys, "_MEIPASS", str(tmp_path), raising=False)

    worker = _robot_parsing_worker_source()
    assert worker == bundled


def test_parsing_worker_source_errors_when_absent(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    missing_dir = tmp_path / "missing"
    missing_dir.mkdir()
    monkeypatch.setattr(
        bridge,
        "__file__",
        str(missing_dir / "robot_parsing_bridge.py"),
    )
    monkeypatch.setattr(bridge.sys, "_MEIPASS", str(tmp_path), raising=False)

    with pytest.raises(RobotParsingError, match="parsing worker is missing"):
        _robot_parsing_worker_source()
