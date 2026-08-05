"""Tests for DocumentAnalysisService and document symbol trees."""

from __future__ import annotations

import pytest

from robot_studio.domain.models.document_symbols import DocumentSymbolTree
from robot_studio.infrastructure.language.document_analysis import (
    DocumentAnalysisService,
)
from robot_studio.infrastructure.language.robot_parsing_worker import (
    document_symbol_tree,
)


SAMPLE = """\
*** Settings ***
Documentation    Suite for login flows
Library    BuiltIn
Resource   common.resource

*** Variables ***
${URL}    https://example.com

*** Keywords ***
Login
    [Documentation]    Shared login helper
    [Arguments]    ${user}
    Log    ${user}
    IF    $True
        Log    inside
    END

*** Test Cases ***
Login Works
    [Documentation]    Example test case
    Login    admin
    FOR    ${i}    IN RANGE    2
        Log    ${i}
    END
"""


def test_document_symbol_tree_nested_structure() -> None:
    tree = document_symbol_tree(SAMPLE, "tests/login.robot")
    root = tree["root"]
    assert root["kind"] == "test_suite"
    assert root["name"] == "login"
    section_names = [child["name"] for child in root["children"]]
    assert section_names == ["Settings", "Variables", "Keywords", "Tests"]

    keywords = next(c for c in root["children"] if c["name"] == "Keywords")
    login = keywords["children"][0]
    assert login["name"] == "Login"
    assert login["kind"] == "keyword"
    call_names = [c["name"] for c in login["children"]]
    assert "Log" in call_names
    assert any(c["kind"] == "control" and c["name"].startswith("IF") for c in login["children"])

    tests = next(c for c in root["children"] if c["name"] == "Tests")
    case = tests["children"][0]
    assert case["name"] == "Login Works"
    assert any(c["name"] == "Login" and c["kind"] == "keyword_call" for c in case["children"])
    assert any(c["kind"] == "control" and "FOR" in c["name"] for c in case["children"])


def test_document_symbol_tree_omits_documentation_children() -> None:
    """Outline must not show [Documentation] under keywords / tests / Settings.

    The text still lives on the parent for hover — only the child row is dropped.
    """
    tree = document_symbol_tree(SAMPLE, "tests/login.robot")
    root = tree["root"]

    settings = next(c for c in root["children"] if c["name"] == "Settings")
    assert all(c["kind"] != "documentation" for c in settings["children"])
    assert all(c["detail"] != "Documentation" for c in settings["children"])
    assert {c["name"] for c in settings["children"]} == {"BuiltIn", "common.resource"}

    keywords = next(c for c in root["children"] if c["name"] == "Keywords")
    login = keywords["children"][0]
    assert login["documentation"] == "Shared login helper"
    assert all(c["kind"] != "documentation" for c in login["children"])

    tests = next(c for c in root["children"] if c["name"] == "Tests")
    case = tests["children"][0]
    assert case["documentation"] == "Example test case"
    assert all(c["kind"] != "documentation" for c in case["children"])


def test_document_symbol_tree_model_find_and_fold() -> None:
    raw = document_symbol_tree(SAMPLE, "tests/login.robot")
    model = DocumentSymbolTree.from_api({**raw, "content_hash": "abc"})
    active = model.active_symbol(10)  # around Login keyword body
    assert active is not None
    folds = model.folding_ranges()
    assert folds
    assert all(f["end_line"] >= f["start_line"] for f in folds)


@pytest.mark.asyncio
async def test_document_analysis_service_caches() -> None:
    calls = {"n": 0}

    async def run_tree(content: str, file_path: str) -> dict:
        calls["n"] += 1
        return document_symbol_tree(content, file_path)

    service = DocumentAnalysisService(_run_tree=run_tree)
    first = await service.analyze("a.robot", SAMPLE)
    second = await service.analyze("a.robot", SAMPLE)
    assert first is second
    assert calls["n"] == 1
    third = await service.analyze("a.robot", SAMPLE + "\n")
    assert third is not first
    assert calls["n"] == 2


def test_document_symbol_filter() -> None:
    raw = document_symbol_tree(SAMPLE, "tests/login.robot")
    tree = DocumentSymbolTree.from_api(raw)
    filtered = tree.filter("Login")
    names = [n.name for n in filtered.flatten()]
    assert "Login" in names
    assert "Login Works" in names
