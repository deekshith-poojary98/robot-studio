"""Variables from ``Variables`` imports and sigil-flexible usage."""

from __future__ import annotations

from pathlib import Path

from robot_studio.infrastructure.language.robot_language_service import (
    RobotLanguageService,
)


def test_collect_variables_from_python_import(tmp_path: Path) -> None:
    env = tmp_path / "env.py"
    env.write_text("KNOWN_POST_ID = 1\n_SKIP = 2\n", encoding="utf-8")
    suite = tmp_path / "suite.robot"
    suite.write_text(
        "*** Settings ***\n"
        "Variables    env.py\n"
        "*** Test Cases ***\n"
        "T\n"
        "    ${posts}=    Create List    a\n"
        "    FOR    ${post}    IN    @{posts}\n"
        "        Log    ${KNOWN_POST_ID}\n"
        "    END\n",
        encoding="utf-8",
    )
    declared = RobotLanguageService._collect_declared_variables(
        suite.read_text(encoding="utf-8").splitlines(),
        file_path=str(suite),
    )
    assert "${KNOWN_POST_ID}" in declared
    assert "${_SKIP}" not in declared
    assert "${posts}" in declared
    assert "${post}" in declared
    assert RobotLanguageService._is_known_variable("@{posts}", declared)
    assert RobotLanguageService._is_known_variable("${KNOWN_POST_ID}", declared)


def test_list_variable_from_resource_python_import(tmp_path: Path) -> None:
    """``@{PROTECTED_PATHS}`` from a Resource → Variables *.py is in suite scope."""
    data = tmp_path / "data.py"
    data.write_text('PROTECTED_PATHS = ["/dashboard"]\n', encoding="utf-8")
    resource = tmp_path / "pages.resource"
    resource.write_text(
        "*** Settings ***\nVariables    data.py\n",
        encoding="utf-8",
    )
    suite = tmp_path / "login_test.robot"
    suite.write_text(
        "*** Settings ***\n"
        "Resource    pages.resource\n"
        "*** Test Cases ***\n"
        "T\n"
        "    FOR    ${path}    IN    @{PROTECTED_PATHS}\n"
        "        Log    ${path}\n"
        "    END\n",
        encoding="utf-8",
    )
    declared = RobotLanguageService._collect_declared_variables(
        suite.read_text(encoding="utf-8").splitlines(),
        file_path=str(suite),
    )
    assert "${PROTECTED_PATHS}" in declared
    assert RobotLanguageService._is_known_variable("@{PROTECTED_PATHS}", declared)
    # Keyword-local assigns in the resource must not leak into the suite.
    resource.write_text(
        "*** Settings ***\n"
        "Variables    data.py\n"
        "*** Keywords ***\n"
        "Helper\n"
        "    ${secret}=    Set Variable    x\n",
        encoding="utf-8",
    )
    declared = RobotLanguageService._collect_declared_variables(
        suite.read_text(encoding="utf-8").splitlines(),
        file_path=str(suite),
    )
    assert RobotLanguageService._is_known_variable("@{PROTECTED_PATHS}", declared)
    assert "${secret}" not in declared


def test_symbol_lookup_names_includes_other_sigils() -> None:
    names = RobotLanguageService._symbol_lookup_names("@{PROTECTED_PATHS}")
    assert "@{PROTECTED_PATHS}" in names
    assert "${PROTECTED_PATHS}" in names
    assert "PROTECTED_PATHS" in names


def test_extended_variable_access_is_known_when_base_declared() -> None:
    declared = {"${response}", "@{items}"}
    assert RobotLanguageService._is_known_variable("${response.json()}", declared)
    assert RobotLanguageService._is_known_variable("${response.status_code}", declared)
    assert RobotLanguageService._is_known_variable("${items[0]}", declared)
    assert RobotLanguageService._is_known_variable("${items[0].name}", declared)
    # Still unknown when the base was never assigned.
    assert not RobotLanguageService._is_known_variable("${other.json()}", declared)
    # Number literals with a decimal must not be treated as attribute access.
    assert RobotLanguageService._is_known_variable("${3.14}", set())
