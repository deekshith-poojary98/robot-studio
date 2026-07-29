"""DSL vs BuiltIn catalog invariants."""

from __future__ import annotations

from robot_studio.infrastructure.language.builtin_keywords import (
    BUILTIN_KEYWORDS,
    COMMON_BUILTIN_KEYWORDS,
    CONTROL_MARKERS,
    LOCAL_SETTINGS,
    SECTION_HEADERS,
    SETTING_NAMES,
)


def test_dsl_markers_are_not_classified_as_builtin() -> None:
    builtin = {name.casefold() for name in BUILTIN_KEYWORDS}
    for marker in CONTROL_MARKERS:
        assert marker.casefold() not in builtin, (
            f"{marker!r} is RF DSL and must not appear in BuiltIn keywords"
        )


def test_common_builtins_are_library_keywords() -> None:
    builtin = {name.casefold() for name in BUILTIN_KEYWORDS}
    for name in COMMON_BUILTIN_KEYWORDS:
        assert name.casefold() in builtin


def test_section_headers_include_comments_and_legacy_singular() -> None:
    assert "*** Comments ***" in SECTION_HEADERS
    assert "*** Setting ***" in SECTION_HEADERS
    assert "*** Test Cases ***" in SECTION_HEADERS


def test_settings_cover_suite_and_local() -> None:
    assert "Library" in SETTING_NAMES
    assert "Suite Setup" in SETTING_NAMES
    assert "[Documentation]" in LOCAL_SETTINGS
    assert "[Arguments]" in LOCAL_SETTINGS
    assert "WITH NAME" in CONTROL_MARKERS
    assert "AND" in CONTROL_MARKERS
