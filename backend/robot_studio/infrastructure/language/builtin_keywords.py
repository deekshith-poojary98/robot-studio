"""Robot Framework language catalogs — DSL vs BuiltIn library keywords.

True **DSL** tokens (section headers, settings, control-flow) are language syntax.
**BuiltIn** keywords ship with Robot Framework but are library keywords and can be
overridden. Keep these separate for highlighting, completion, and diagnostics.

Taxonomy aligned with the Robot Framework User Guide and IDE token classification.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# Section headers (primary + legacy singular)
# ---------------------------------------------------------------------------

SECTION_HEADERS: list[str] = [
    "*** Settings ***",
    "*** Variables ***",
    "*** Test Cases ***",
    "*** Tasks ***",
    "*** Keywords ***",
    "*** Comments ***",
    # Legacy singular forms (still accepted by RF)
    "*** Setting ***",
    "*** Variable ***",
    "*** Test Case ***",
    "*** Task ***",
    "*** Keyword ***",
    "*** Comment ***",
]

# ---------------------------------------------------------------------------
# Settings — suite / imports (*** Settings ***)
# ---------------------------------------------------------------------------

SUITE_SETTINGS: list[str] = [
    "Documentation",
    "Metadata",
    "Name",
    "Suite Setup",
    "Suite Teardown",
    "Test Setup",
    "Test Teardown",
    "Test Timeout",
    "Test Tags",
    "Default Tags",
    "Force Tags",  # deprecated alias; still seen in suites
    "Keyword Tags",
    "Library",
    "Resource",
    "Variables",
    # Task aliases (RF tasks)
    "Task Setup",
    "Task Teardown",
    "Task Template",
    "Task Timeout",
    "Test Template",
]

IMPORT_SETTINGS: list[str] = [
    "Library",
    "Resource",
    "Variables",
]

# Back-compat alias used by language service / older imports.
SETTING_NAMES: list[str] = list(dict.fromkeys(SUITE_SETTINGS))

# ---------------------------------------------------------------------------
# Local settings — Test Case / Task / Keyword bodies
# ---------------------------------------------------------------------------

TEST_CASE_SETTINGS: list[str] = [
    "[Documentation]",
    "[Tags]",
    "[Setup]",
    "[Teardown]",
    "[Timeout]",
    "[Template]",
]

KEYWORD_SETTINGS: list[str] = [
    "[Documentation]",
    "[Arguments]",
    "[Setup]",
    "[Teardown]",
    "[Timeout]",
    "[Tags]",
    "[Return]",  # deprecated; prefer RETURN statement
]

LOCAL_SETTINGS: list[str] = list(
    dict.fromkeys([*TEST_CASE_SETTINGS, *KEYWORD_SETTINGS]),
)

# ---------------------------------------------------------------------------
# Control-flow / RF DSL markers (NOT library keywords)
# ---------------------------------------------------------------------------

CONTROL_MARKERS: list[str] = [
    "IF",
    "ELSE IF",
    "ELSE",
    "END",
    "FOR",
    "IN",
    "IN RANGE",
    "IN ENUMERATE",
    "IN ZIP",
    "WHILE",
    "TRY",
    "EXCEPT",
    "FINALLY",
    "BREAK",
    "CONTINUE",
    "RETURN",
    "VAR",
    "GROUP",
    "WITH NAME",
    "AS",
    "AND",
]

# Completion entries (snippets). kind should be reported as "dsl".
CONTROL_STRUCTURES: list[dict[str, str]] = [
    {
        "label": "FOR",
        "detail": "RF DSL · control flow",
        "documentation": "Language loop — not a BuiltIn keyword.",
        "insert_text": "FOR    ${item}    IN    @{list}\n    Log    ${item}\nEND",
    },
    {
        "label": "FOR … IN RANGE",
        "detail": "RF DSL · control flow",
        "documentation": "FOR ${i} IN RANGE    10 … END",
        "insert_text": "FOR    ${i}    IN RANGE    10\n    Log    ${i}\nEND",
    },
    {
        "label": "FOR … IN ENUMERATE",
        "detail": "RF DSL · control flow",
        "documentation": "FOR ${index} ${item} IN ENUMERATE    @{list} … END",
        "insert_text": "FOR    ${index}    ${item}    IN ENUMERATE    @{list}\n    Log    ${index}: ${item}\nEND",
    },
    {
        "label": "FOR … IN ZIP",
        "detail": "RF DSL · control flow",
        "documentation": "FOR ${a} ${b} IN ZIP    @{list1}    @{list2} … END",
        "insert_text": "FOR    ${a}    ${b}    IN ZIP    @{list1}    @{list2}\n    Log    ${a} ${b}\nEND",
    },
    {
        "label": "WHILE",
        "detail": "RF DSL · control flow",
        "documentation": "WHILE    ${condition} … END",
        "insert_text": "WHILE    ${condition}\n    Log    looping\nEND",
    },
    {
        "label": "IF",
        "detail": "RF DSL · control flow",
        "documentation": "IF    ${condition} … END",
        "insert_text": "IF    ${condition}\n    Log    yes\nEND",
    },
    {
        "label": "IF / ELSE",
        "detail": "RF DSL · control flow",
        "documentation": "IF … ELSE … END",
        "insert_text": "IF    ${condition}\n    Log    yes\nELSE\n    Log    no\nEND",
    },
    {
        "label": "IF / ELSE IF / ELSE",
        "detail": "RF DSL · control flow",
        "documentation": "IF … ELSE IF … ELSE … END",
        "insert_text": "IF    ${condition}\n    Log    a\nELSE IF    ${other}\n    Log    b\nELSE\n    Log    c\nEND",
    },
    {
        "label": "ELSE",
        "detail": "RF DSL · control flow",
        "documentation": "Branch of an IF / TRY structure",
        "insert_text": "ELSE",
    },
    {
        "label": "ELSE IF",
        "detail": "RF DSL · control flow",
        "documentation": "Additional IF condition branch",
        "insert_text": "ELSE IF    ${condition}",
    },
    {
        "label": "TRY / EXCEPT",
        "detail": "RF DSL · control flow",
        "documentation": "TRY … EXCEPT … END",
        "insert_text": "TRY\n    Fail    boom\nEXCEPT    *\n    Log    handled\nEND",
    },
    {
        "label": "TRY",
        "detail": "RF DSL · control flow",
        "documentation": "Start a TRY block",
        "insert_text": "TRY",
    },
    {
        "label": "EXCEPT",
        "detail": "RF DSL · control flow",
        "documentation": "Catch errors in a TRY block",
        "insert_text": "EXCEPT    *",
    },
    {
        "label": "FINALLY",
        "detail": "RF DSL · control flow",
        "documentation": "Always run after TRY / EXCEPT",
        "insert_text": "FINALLY",
    },
    {
        "label": "BREAK",
        "detail": "RF DSL · control flow",
        "documentation": "Exit the current FOR / WHILE loop",
        "insert_text": "BREAK",
    },
    {
        "label": "CONTINUE",
        "detail": "RF DSL · control flow",
        "documentation": "Continue to the next FOR / WHILE iteration",
        "insert_text": "CONTINUE",
    },
    {
        "label": "RETURN",
        "detail": "RF DSL · control flow",
        "documentation": "Return from a user keyword (preferred over [Return])",
        "insert_text": "RETURN",
    },
    {
        "label": "END",
        "detail": "RF DSL · control flow",
        "documentation": "Ends FOR / WHILE / IF / TRY / GROUP blocks",
        "insert_text": "END",
    },
    {
        "label": "GROUP",
        "detail": "RF DSL · control flow",
        "documentation": "GROUP    name … END",
        "insert_text": "GROUP    related steps\n    Log    step\nEND",
    },
    {
        "label": "VAR",
        "detail": "RF DSL · control flow",
        "documentation": "VAR    ${name}    value",
        "insert_text": "VAR    ${name}    value",
    },
    {
        "label": "IN",
        "detail": "RF DSL · control flow",
        "documentation": "FOR ${item} IN @{list}",
        "insert_text": "IN",
    },
    {
        "label": "IN RANGE",
        "detail": "RF DSL · control flow",
        "documentation": "FOR ${i} IN RANGE    start    stop",
        "insert_text": "IN RANGE",
    },
    {
        "label": "IN ENUMERATE",
        "detail": "RF DSL · control flow",
        "documentation": "FOR ${index} ${item} IN ENUMERATE    @{list}",
        "insert_text": "IN ENUMERATE",
    },
    {
        "label": "IN ZIP",
        "detail": "RF DSL · control flow",
        "documentation": "FOR ${a} ${b} IN ZIP    @{a}    @{b}",
        "insert_text": "IN ZIP",
    },
    {
        "label": "WITH NAME",
        "detail": "RF DSL · import alias",
        "documentation": "Library    SeleniumLibrary    WITH NAME    Selenium",
        "insert_text": "WITH NAME",
    },
    {
        "label": "AS",
        "detail": "RF DSL · EXCEPT / alias",
        "documentation": "EXCEPT    error    AS    ${msg}",
        "insert_text": "AS",
    },
    {
        "label": "AND",
        "detail": "RF DSL · Run Keywords separator",
        "documentation": "Run Keywords    Kw1    AND    Kw2",
        "insert_text": "AND",
    },
]

# ---------------------------------------------------------------------------
# BuiltIn library keywords (NOT DSL — can be overridden)
# ---------------------------------------------------------------------------

BUILTIN_KEYWORDS: list[str] = [
    "Call Method",
    "Catenate",
    "Comment",
    "Continue For Loop",
    "Continue For Loop If",
    "Convert To Binary",
    "Convert To Boolean",
    "Convert To Bytes",
    "Convert To Hex",
    "Convert To Integer",
    "Convert To Number",
    "Convert To Octal",
    "Convert To String",
    "Create Dictionary",
    "Create List",
    "Evaluate",
    "Exit For Loop",
    "Exit For Loop If",
    "Fail",
    "Fatal Error",
    "Get Count",
    "Get Length",
    "Get Library Instance",
    "Get Time",
    "Get Variable Value",
    "Get Variables",
    "Import Library",
    "Import Resource",
    "Import Variables",
    "Keyword Should Exist",
    "Length Should Be",
    "Log",
    "Log Many",
    "Log To Console",
    "Log Variables",
    "No Operation",
    "Pass Execution",
    "Pass Execution If",
    "Regexp Escape",
    "Reload Library",
    "Remove Tags",
    "Repeat Keyword",
    "Replace Variables",
    "Reset Log Level",
    "Return From Keyword",
    "Return From Keyword If",
    "Run Keyword",
    "Run Keyword And Continue On Failure",
    "Run Keyword And Expect Error",
    "Run Keyword And Ignore Error",
    "Run Keyword And Return",
    "Run Keyword And Return If",
    "Run Keyword And Return Status",
    "Run Keyword And Warn On Failure",
    "Run Keyword If",
    "Run Keyword If All Tests Passed",
    "Run Keyword If Any Tests Failed",
    "Run Keyword If Test Failed",
    "Run Keyword If Test Passed",
    "Run Keyword If Timeout Occurred",
    "Run Keyword Unless",
    "Run Keywords",
    "Set Global Variable",
    "Set Library Search Order",
    "Set Local Variable",
    "Set Log Level",
    "Set Suite Documentation",
    "Set Suite Metadata",
    "Set Suite Variable",
    "Set Tags",
    "Set Task Variable",
    "Set Test Documentation",
    "Set Test Message",
    "Set Test Variable",
    "Set Variable",
    "Set Variable If",
    "Should Be Empty",
    "Should Be Equal",
    "Should Be Equal As Integers",
    "Should Be Equal As Numbers",
    "Should Be Equal As Strings",
    "Should Be True",
    "Should Contain",
    "Should Contain Any",
    "Should Contain X Times",
    "Should End With",
    "Should Match",
    "Should Match Regexp",
    "Should Not Be Empty",
    "Should Not Be Equal",
    "Should Not Be Equal As Integers",
    "Should Not Be Equal As Numbers",
    "Should Not Be Equal As Strings",
    "Should Not Be True",
    "Should Not Contain",
    "Should Not Contain Any",
    "Should Not End With",
    "Should Not Match",
    "Should Not Match Regexp",
    "Should Not Start With",
    "Should Start With",
    "Skip",
    "Skip If",
    "Sleep",
    "Variable Should Exist",
    "Variable Should Not Exist",
    "Wait Until Keyword Succeeds",
]

# Frequently mistaken for DSL — kept as an explicit subset for docs/tests.
COMMON_BUILTIN_KEYWORDS: list[str] = [
    "Log",
    "Log To Console",
    "No Operation",
    "Should Be Equal",
    "Should Contain",
    "Should Be True",
    "Run Keyword",
    "Run Keywords",
    "Run Keyword If",
    "Repeat Keyword",
    "Wait Until Keyword Succeeds",
    "Set Variable",
    "Create List",
    "Create Dictionary",
    "Evaluate",
    "Import Library",
    "Import Resource",
    "Import Variables",
    "Fail",
    "Pass Execution",
    "Skip",
    "Sleep",
]

# File / syntax notes (documentation helpers — not completion lists).
ROBOT_FILE_EXTENSIONS: tuple[str, ...] = (".robot", ".resource")
SPECIAL_SUITE_FILES: tuple[str, ...] = ("__init__.robot",)
CONTINUATION_MARKER = "..."
VARIABLE_PREFIXES: tuple[str, ...] = ("${", "@{", "&{", "%{")
