"""Robot Framework listener — emit current suite/test/keyword for Live Execution.

Loaded by absolute path via ``--listener`` so it works in the project's venv
without installing Robot Studio there. Writes one marker line per change:

    ###RS###|now|<suite>|<test>|<keyword>

Robot often leaves the console cursor mid-line (padded suite/test names), so we
always start the marker on a fresh line. The Studio UI strips markers from Live
Output and shows them in the "Now running" panel.
"""

from __future__ import annotations

import sys

ROBOT_LISTENER_API_VERSION = 2

_PREFIX = "###RS###|now|"
_suite = ""
_test = ""
_keyword_stack: list[str] = []


def _safe(value: object) -> str:
    return str(value or "").replace("|", "/").replace("\n", " ").strip()


def _emit() -> None:
    keyword = _keyword_stack[-1] if _keyword_stack else ""
    # Leading newline: Robot console frequently prints suite/test names without
    # finishing the line; a bare print() would glue the marker onto that row.
    sys.stdout.write(
        f"\n{_PREFIX}{_safe(_suite)}|{_safe(_test)}|{_safe(keyword)}\n"
    )
    sys.stdout.flush()


def start_suite(name, attrs):  # noqa: ANN001, ARG001
    global _suite, _test
    _suite = name
    _test = ""
    _keyword_stack.clear()
    _emit()


def end_suite(name, attrs):  # noqa: ANN001, ARG001
    global _suite, _test
    _suite = ""
    _test = ""
    _keyword_stack.clear()
    _emit()


def start_test(name, attrs):  # noqa: ANN001, ARG001
    global _test
    _test = name
    _keyword_stack.clear()
    _emit()


def end_test(name, attrs):  # noqa: ANN001, ARG001
    global _test
    _test = ""
    _keyword_stack.clear()
    _emit()


def start_keyword(name, attrs):  # noqa: ANN001
    attrs = attrs or {}
    kw = attrs.get("kwname") or name
    lib = attrs.get("libname") or ""
    # Skip control/setup wrappers that are not user-facing "now running".
    kind = str(attrs.get("type") or "").upper()
    if kind in {"FOR", "ITER", "IF", "ELSE IF", "ELSE", "TRY", "EXCEPT", "FINALLY", "WHILE"}:
        return
    label = _safe(kw)
    lib_s = _safe(lib)
    if lib_s and not label.lower().startswith(f"{lib_s.lower()}."):
        label = f"{lib_s}.{label}"
    _keyword_stack.append(label)
    _emit()


def end_keyword(name, attrs):  # noqa: ANN001, ARG001
    attrs = attrs or {}
    kind = str(attrs.get("type") or "").upper()
    if kind in {"FOR", "ITER", "IF", "ELSE IF", "ELSE", "TRY", "EXCEPT", "FINALLY", "WHILE"}:
        return
    if _keyword_stack:
        _keyword_stack.pop()
    _emit()
