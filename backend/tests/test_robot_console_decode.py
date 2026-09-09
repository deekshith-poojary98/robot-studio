"""Console decode helpers for Robot Live Output."""

from robot_studio.infrastructure.execution.console_decode import (
    decode_robot_console_line,
)


def test_decode_utf8_middle_dot() -> None:
    assert decode_robot_console_line("TC · Dashboard\n".encode("utf-8")) == "TC · Dashboard"


def test_decode_cp1252_middle_dot_does_not_become_replacement() -> None:
    # Windows console often emits U+00B7 as the single cp1252 byte 0xB7.
    line = b"TC-DASH-001 \xb7 Dashboard loads :: Doc | FAIL |\n"
    text = decode_robot_console_line(line)
    assert "\ufffd" not in text
    assert text == "TC-DASH-001 · Dashboard loads :: Doc | FAIL |"


def test_decode_strips_crlf() -> None:
    assert decode_robot_console_line(b"ok\r\n") == "ok"
