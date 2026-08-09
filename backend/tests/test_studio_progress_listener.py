"""Tests for the Studio progress listener markers."""

from __future__ import annotations

import io
from contextlib import redirect_stdout

from robot_studio.infrastructure.execution import studio_progress_listener as listener


def test_progress_markers_track_innermost_keyword() -> None:
    buf = io.StringIO()
    with redirect_stdout(buf):
        listener.start_suite("Demo", {})
        listener.start_test("Hello", {})
        listener.start_keyword(
            "Log",
            {"kwname": "Log", "libname": "BuiltIn", "type": "KEYWORD"},
        )
        listener.start_keyword(
            "Should Be Equal",
            {
                "kwname": "Should Be Equal",
                "libname": "BuiltIn",
                "type": "KEYWORD",
            },
        )
        listener.end_keyword("Should Be Equal", {"type": "KEYWORD"})
        listener.end_keyword("Log", {"type": "KEYWORD"})
        listener.end_test("Hello", {})
        listener.end_suite("Demo", {})

    lines = [line for line in buf.getvalue().splitlines() if line.startswith("###RS###|now|")]
    assert lines[0] == "###RS###|now|Demo||"
    assert lines[1] == "###RS###|now|Demo|Hello|"
    assert lines[2] == "###RS###|now|Demo|Hello|BuiltIn.Log"
    assert lines[3] == "###RS###|now|Demo|Hello|BuiltIn.Should Be Equal"
    assert lines[4] == "###RS###|now|Demo|Hello|BuiltIn.Log"
    assert lines[5] == "###RS###|now|Demo|Hello|"
    assert lines[6] == "###RS###|now|Demo||"
    assert lines[7] == "###RS###|now|||"


def test_control_structures_do_not_replace_keyword() -> None:
    buf = io.StringIO()
    with redirect_stdout(buf):
        listener.start_suite("S", {})
        listener.start_test("T", {})
        listener.start_keyword("Log", {"kwname": "Log", "libname": "BuiltIn"})
        listener.start_keyword("${i} IN [1, 2]", {"type": "FOR", "kwname": "FOR"})
        listener.end_keyword("${i} IN [1, 2]", {"type": "FOR"})
        listener.end_keyword("Log", {})

    lines = [line for line in buf.getvalue().splitlines() if line.startswith("###RS###|now|")]
    assert "###RS###|now|S|T|BuiltIn.Log" in lines
    assert not any("|FOR" in line for line in lines)
