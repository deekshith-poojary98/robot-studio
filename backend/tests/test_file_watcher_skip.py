"""File watcher should ignore run-artifact churn."""

from pathlib import Path

from robot_studio.infrastructure.indexing.file_watcher import _is_skipped


def test_skips_robotstudio_reports_and_artifacts() -> None:
    root = Path("/proj/.robotstudio/reports/Run-1/output.xml")
    assert _is_skipped(root) is True
    assert _is_skipped(Path("/proj/.robotstudio/reports/Run-1")) is True
    assert _is_skipped(Path("/proj/.robotstudio/environments/venv")) is True
    assert _is_skipped(Path("/tmp/custom/output.xml")) is True
    assert _is_skipped(Path("/proj/tests/login.robot")) is False
    assert _is_skipped(Path("/proj/CustomLib.py")) is False
