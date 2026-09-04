"""Variable indexing covers declarations beyond *** Variables ***."""

from __future__ import annotations

from robot_studio.infrastructure.language.robot_parsing_worker import document_symbols

SAMPLE = """*** Variables ***
${USER}    alice

*** Keywords ***
Login User
    [Arguments]    ${username}    ${password}=secret
    VAR    ${local}    Hello
    ${x}=    Set Variable    1
    FOR    ${i}    IN RANGE    3
        Log    ${i}
    END
    ${a}    ${b}=    Create List    1    2

*** Test Cases ***
Verify Login
    ${result}=    Set Variable    ok
    Login User    a    b
"""


def test_document_symbols_indexes_all_variable_forms() -> None:
    symbols = document_symbols(SAMPLE, "demo.robot")
    variables = [
        (item["name"], item.get("detail") or "")
        for item in symbols
        if item.get("kind") == "variable"
    ]
    by_name = {name: detail for name, detail in variables}

    assert by_name["${USER}"] == "Variables"
    assert by_name["${username}"] == "Argument"
    assert by_name["${password}"] == "Argument"
    assert by_name["${local}"] == "VAR"
    assert by_name["${x}"] == "Assignment"
    assert by_name["${i}"] == "FOR"
    assert by_name["${a}"] == "Assignment"
    assert by_name["${b}"] == "Assignment"
    assert by_name["${result}"] == "Assignment"

    assert len(variables) == 9
