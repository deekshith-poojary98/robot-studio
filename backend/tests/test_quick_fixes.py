"""Unit tests for diagnostic quick-fix hints (install / insert Library)."""

from __future__ import annotations

from robot_studio.infrastructure.language.quick_fixes import (
    insert_library_import,
    library_qualifier,
    pypi_package_for_import,
    pypi_package_for_library,
    quick_fix_hint,
)


def test_pypi_mapping_for_common_robot_libraries() -> None:
    assert pypi_package_for_library("RequestsLibrary") == "robotframework-requests"
    assert pypi_package_for_library("SeleniumLibrary") == "robotframework-seleniumlibrary"
    assert pypi_package_for_library("../../ExcelSage.py") is None
    assert pypi_package_for_library("NotARealLibrary") is None


def test_pypi_mapping_for_python_imports() -> None:
    assert pypi_package_for_import("pandas") == "pandas"
    assert pypi_package_for_import("yaml") == "pyyaml"
    assert pypi_package_for_import("cv2") == "opencv-python"


def test_library_qualifier_from_unknown_keyword() -> None:
    assert library_qualifier("RequestsLibrary.GET On Session") == "RequestsLibrary"
    assert library_qualifier("Open Browser") is None
    assert library_qualifier("BuiltIn.Log") is None
    assert library_qualifier("${obj}.method") is None


def test_insert_library_into_existing_settings() -> None:
    content = "*** Settings ***\nLibrary    Collections\n\n*** Test Cases ***\nDemo\n    Log    hi\n"
    updated = insert_library_import(content, "RequestsLibrary")
    assert updated is not None
    assert "Library    RequestsLibrary" in updated
    # After the last Library row, before the next section.
    assert updated.index("Library    RequestsLibrary") < updated.index("*** Test Cases ***")
    assert insert_library_import(updated, "RequestsLibrary") is None


def test_insert_library_creates_settings_section() -> None:
    content = "*** Test Cases ***\nDemo\n    Log    hi\n"
    updated = insert_library_import(content, "RequestsLibrary")
    assert updated is not None
    assert updated.startswith("*** Settings ***")
    assert "Library    RequestsLibrary" in updated
    assert "*** Test Cases ***" in updated


def test_quick_fix_missing_library_installs_package() -> None:
    hint = quick_fix_hint(
        code="missing_library",
        message="Missing library 'RequestsLibrary'",
    )
    assert hint == {
        "kind": "install_package",
        "title": "Install robotframework-requests",
        "package": "robotframework-requests",
    }


def test_quick_fix_unknown_keyword_inserts_library() -> None:
    content = "*** Test Cases ***\nDemo\n    RequestsLibrary.GET On Session    alias\n"
    hint = quick_fix_hint(
        code="unknown_keyword",
        message="Unknown keyword 'RequestsLibrary.GET On Session'",
        content=content,
    )
    assert hint is not None
    assert hint["kind"] == "insert_library"
    assert hint["library"] == "RequestsLibrary"


def test_quick_fix_missing_package_installs_import() -> None:
    hint = quick_fix_hint(
        code="missing_package",
        message="Cannot find package 'pandas' in the active environment",
    )
    assert hint == {
        "kind": "install_package",
        "title": "Install pandas",
        "package": "pandas",
    }
