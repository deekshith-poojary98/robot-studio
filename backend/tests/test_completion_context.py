"""Completion context for settings that take a keyword (setup / teardown / template)."""

from __future__ import annotations

import pytest
from robot_studio.domain.interfaces.completion import CompletionRequestContext
from robot_studio.infrastructure.language.completion.dsl_provider import (
    SettingCompletionProvider,
)
from robot_studio.infrastructure.language.robot_parsing_worker import (
    completion_context,
    signature_help,
)


def _col_after(row: str, token: str) -> int:
    return row.index(token) + len(token) + 1


def test_suite_setup_keyword_prefix_is_keyword_call() -> None:
    content = """*** Settings ***
Suite Setup    Ope
"""
    row = content.splitlines()[1]
    ctx = completion_context(content, "x.robot", 2, _col_after(row, "Ope"))
    assert ctx["context"] == "keyword_call"
    assert ctx["section"] == "settings"
    assert ctx["prefix"] == "Ope"


def test_test_teardown_empty_slot_is_keyword_call() -> None:
    content = "*** Settings ***\nTest Teardown    \n"
    row = content.splitlines()[1]
    ctx = completion_context(content, "x.robot", 2, len(row) + 1)
    assert ctx["context"] == "keyword_call"
    assert ctx["prefix"] == ""


def test_suite_setup_name_itself_stays_setting() -> None:
    content = "*** Settings ***\nSuite Setup\n"
    row = content.splitlines()[1]
    ctx = completion_context(content, "x.robot", 2, len(row) + 1)
    assert ctx["context"] == "setting"
    assert ctx["prefix"] == "Suite Setup"


def test_documentation_stays_setting() -> None:
    content = "*** Settings ***\nDocumentation    Test suite descript\n"
    row = content.splitlines()[1]
    ctx = completion_context(content, "x.robot", 2, _col_after(row, "descript"))
    assert ctx["context"] == "setting"


def test_suite_setup_arguments_use_keyword() -> None:
    content = """*** Settings ***
Suite Setup    Open Browser    https://example.com
"""
    row = content.splitlines()[1]
    ctx = completion_context(content, "x.robot", 2, _col_after(row, "https://example.com"))
    assert ctx["context"] == "argument"
    assert ctx["keyword"] == "Open Browser"
    assert ctx["prefix"] == "https://example.com"


def test_suite_setup_continuation_is_argument() -> None:
    content = """*** Settings ***
Suite Setup    Open Browser    https://example.com
...    chrome
"""
    row = content.splitlines()[2]
    ctx = completion_context(content, "x.robot", 3, _col_after(row, "chrome"))
    assert ctx["context"] == "argument"
    assert ctx["keyword"] == "Open Browser"
    assert ctx["prefix"] == "chrome"


def test_local_setup_keyword_is_keyword_call() -> None:
    content = """*** Test Cases ***
Login
    [Setup]    Ope
"""
    row = content.splitlines()[2]
    ctx = completion_context(content, "login.robot", 3, _col_after(row, "Ope"))
    assert ctx["context"] == "keyword_call"
    assert ctx["prefix"] == "Ope"


def test_local_setup_name_stays_local_setting() -> None:
    content = """*** Test Cases ***
Login
    [Setup]
"""
    row = content.splitlines()[2]
    ctx = completion_context(content, "login.robot", 3, _col_after(row, "[Setup]"))
    assert ctx["context"] == "local_setting"
    assert ctx["prefix"].startswith("[Setup")


def test_signature_help_on_suite_setup_args() -> None:
    content = """*** Settings ***
Suite Setup    Open Browser    https://example.com
"""
    row = content.splitlines()[1]
    parsed = signature_help(content, "x.robot", 2, _col_after(row, "https://example.com"))
    assert parsed is not None
    assert parsed["keyword"] == "Open Browser"
    assert parsed["in_arguments"] is True


def test_hover_on_test_teardown_keyword() -> None:
    content = "*** Settings ***\nTest Teardown    Close Browser\n"
    row = content.splitlines()[1]
    col = row.index("Close Browser") + 1
    parsed = signature_help(content, "x.robot", 2, col, hover=True)
    assert parsed is not None
    assert parsed["keyword"] == "Close Browser"


@pytest.mark.asyncio
async def test_settings_provider_silent_in_setup_keyword_slot() -> None:
    provider = SettingCompletionProvider()
    items = await provider.complete(
        CompletionRequestContext(
            file_path="x.robot",
            content="",
            line=2,
            column=16,
            prefix="Ope",
            context="keyword_call",
            section="settings",
        ),
    )
    assert items == []
