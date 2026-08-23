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
