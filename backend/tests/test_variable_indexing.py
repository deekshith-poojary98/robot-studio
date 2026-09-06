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


def test_document_symbols_handles_if_elseif_orelse_chain() -> None:
    """Robot stores ELSE IF/ELSE as linked ``If.orelse`` nodes, not a list."""
    source = """*** Keywords ***
Visibility Check
    [Arguments]    ${toggle}=${NONE}
    IF    '${toggle}'=='new'
        ${x}=    Set Variable    new
    ELSE IF    '${toggle}'=='confirm'
        ${y}=    Set Variable    confirm
    ELSE
        ${z}=    Set Variable    none
    END
"""
    symbols = document_symbols(source, "reset_flow.robot")
    names = {item["name"] for item in symbols}
    assert "Visibility Check" in names
    variables = {
        item["name"] for item in symbols if item.get("kind") == "variable"
    }
    assert "${toggle}" in variables
    assert "${x}" in variables
    assert "${y}" in variables
    assert "${z}" in variables
