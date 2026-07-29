*** Settings ***
Documentation       Robot Framework Syntax Highlight Test
Metadata            Author    Deekshith
Metadata            Version   1.0
Suite Setup         Log    Suite Setup
Suite Teardown      Log    Suite Teardown
Test Setup          Log    Test Setup
Test Teardown       Log    Test Teardown
Test Timeout        2 minutes
Test Tags           smoke    regression
Default Tags        default
Keyword Tags        helper
Library             BuiltIn
Library             Collections    WITH NAME    Col
Resource            keywords.resource
Variables           variables.py

*** Variables ***
${URL}              https://example.com
${NUMBER}           42
${EMPTY}
${NONE}             ${None}
@{LIST}             one    two    three
&{DICT}             name=Robot    version=7.0
%{HOME}

*** Comments ***
This is a comment section.
Useful for syntax highlighting.

*** Test Cases ***
Simple Test
    [Documentation]    Demonstrates BuiltIn keywords
    [Tags]    smoke    fast
    [Setup]    Log    Test setup
    [Teardown]    Log    Test teardown
    [Timeout]    30 seconds

    Log    Hello World
    Log To Console    Console output

    ${value}=    Set Variable    123
    @{items}=    Create List    A    B    C
    &{map}=      Create Dictionary    a=1    b=2

    Should Be Equal    ${value}    123
    Should Not Be Equal    ${value}    456
    Should Be True    ${TRUE}
    Should Not Be True    ${FALSE}
    Should Contain    ${URL}    example
    Should Start With    ${URL}    https
    Should End With    ${URL}    .com

    No Operation
    Sleep    100ms

Assignments
    ${result}=    Evaluate    1 + 2
    Log    ${result}

    ${text}=    Catenate
    ...    Hello
    ...    Robot
    ...    Framework

    Log    ${text}

If Example
    IF    ${NUMBER} > 50
        Log    Greater
    ELSE IF    ${NUMBER} == 42
        Log    Forty Two
    ELSE
        Log    Other
    END

Nested IF
    IF    ${TRUE}
        IF    ${FALSE}
            Fail
        ELSE
            Log    Nested
        END
    END

For Loop
    FOR    ${item}    IN    @{LIST}
        Log    ${item}
    END

For Range
    FOR    ${i}    IN RANGE    5
        Log    ${i}
    END

For Enumerate
    FOR    ${index}    ${item}    IN ENUMERATE    @{LIST}
        Log    ${index}: ${item}
    END

For Zip
    @{letters}=    Create List    A    B    C
    FOR    ${a}    ${b}    IN ZIP    @{LIST}    @{letters}
        Log    ${a} ${b}
    END

While Example
    ${i}=    Set Variable    0
    WHILE    ${i} < 5
        Log    ${i}
        ${i}=    Evaluate    ${i}+1

        IF    ${i} == 2
            CONTINUE
        END

        IF    ${i} == 4
            BREAK
        END
    END

Try Example
    TRY
        Fail    Boom
    EXCEPT    Boom
        Log    Exception handled
    ELSE
        Log    No exception
    FINALLY
        Log    Always runs
    END

Run Keyword Example
    Run Keyword    Log    Executed
    Run Keywords
    ...    Log    First
    ...    AND
    ...    Log    Second

Run Keyword If
    Run Keyword If    ${TRUE}    Log    Condition met

Wait Example
    Wait Until Keyword Succeeds
    ...    3x
    ...    100ms
    ...    Log
    ...    Success

Skip Example
    Skip    Demonstration

Pass Example
    Pass Execution    Done

Group Example
    GROUP    Login
        Log    Step 1
        Log    Step 2
    END

Var Example
    VAR    ${local}    Hello
    VAR    @{numbers}    1    2    3
    VAR    &{user}    name=Robot    age=20

Keyword Call
    Example Keyword    Hello

*** Keywords ***
Example Keyword
    [Documentation]    Example keyword
    [Arguments]    ${message}
    [Tags]    helper
    [Setup]    Log    Keyword setup
    [Teardown]    Log    Keyword teardown
    [Timeout]    5 seconds

    Log    ${message}
    RETURN    ${message}

Keyword With IF
    [Arguments]    ${value}

    IF    $value > 10
        RETURN    Big
    END

    RETURN    Small

Keyword With TRY
    TRY
        Log    Inside keyword
    EXCEPT
        Fail
    FINALLY
        Log    Cleanup
    END
