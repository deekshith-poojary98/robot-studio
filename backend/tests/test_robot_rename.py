"""Unit tests for Robot keyword rename rewrites."""

from __future__ import annotations

from robot_studio.infrastructure.language.robot_rename import (
    is_robot_keyword_name,
    replace_keyword_name,
)


def test_replace_keyword_definition_and_call() -> None:
    content = """*** Keywords ***
Login User
    Log    hi

*** Test Cases ***
Demo
    Login User
    Given Login User
"""
    updated = replace_keyword_name(content, "Login User", "Sign In")
    assert "Sign In" in updated
    assert "Login User" not in updated
    assert "Given Sign In" in updated


def test_replace_preserves_library_qualifier() -> None:
    content = "*** Test Cases ***\nDemo\n    MyLib.Login User    x\n"
    updated = replace_keyword_name(content, "Login User", "Sign In")
    assert "MyLib.Sign In" in updated


def test_replace_is_a_no_op_for_unrelated_keywords() -> None:
    content = "*** Test Cases ***\nDemo\n    Log    hi\n"
    assert replace_keyword_name(content, "Login User", "Sign In") == content


def test_robot_keyword_name_rejects_headers() -> None:
    assert is_robot_keyword_name("Sign In")
    assert not is_robot_keyword_name("*** Keywords ***")
    assert not is_robot_keyword_name("a\nb")
