"""Parent ``__init__.robot`` Suite Setup is included when running one file."""

from pathlib import Path

from robot_studio.infrastructure.execution.parent_suite_target import (
    expand_parent_suite_target,
    robot_suite_name_from_path,
)


def test_robot_suite_name_matches_robot_framework() -> None:
    assert robot_suite_name_from_path(Path("posts_api.robot")) == "Posts Api"
    assert robot_suite_name_from_path(Path("tests")) == "Tests"
    assert robot_suite_name_from_path(Path("01__smoke.robot")) == "Smoke"


def test_expand_is_noop_without_parent_init(tmp_path: Path) -> None:
    suite = tmp_path / "tests" / "login.robot"
    suite.parent.mkdir()
    suite.write_text("*** Test Cases ***\nA\n    No Operation\n", encoding="utf-8")
    expanded = expand_parent_suite_target(suite, tmp_path)
    assert expanded.data_source == suite.resolve()
    assert expanded.filter_args == ()


def test_expand_file_run_starts_at_parent_init(tmp_path: Path) -> None:
    tests = tmp_path / "tests"
    nested = tests / "posts"
    nested.mkdir(parents=True)
    (tests / "__init__.robot").write_text(
        "*** Settings ***\nSuite Setup    No Operation\n",
        encoding="utf-8",
    )
    suite = nested / "posts_api.robot"
    suite.write_text("*** Test Cases ***\nA\n    No Operation\n", encoding="utf-8")

    expanded = expand_parent_suite_target(suite, tmp_path)
    assert expanded.data_source == tests.resolve()
    assert expanded.filter_args == ("--suite", "Tests.Posts.Posts Api")


def test_expand_directory_run_keeps_parent_init(tmp_path: Path) -> None:
    tests = tmp_path / "tests"
    nested = tests / "posts"
    nested.mkdir(parents=True)
    (tests / "__init__.robot").write_text(
        "*** Settings ***\nSuite Setup    No Operation\n",
        encoding="utf-8",
    )
    (nested / "posts_api.robot").write_text(
        "*** Test Cases ***\nA\n    No Operation\n",
        encoding="utf-8",
    )

    expanded = expand_parent_suite_target(nested, tmp_path)
    assert expanded.data_source == tests.resolve()
    assert expanded.filter_args == ("--suite", "Tests.Posts")


def test_expand_running_the_init_directory_has_no_filter(tmp_path: Path) -> None:
    tests = tmp_path / "tests"
    tests.mkdir()
    (tests / "__init__.robot").write_text(
        "*** Settings ***\nSuite Setup    No Operation\n",
        encoding="utf-8",
    )
    expanded = expand_parent_suite_target(tests, tmp_path)
    assert expanded.data_source == tests.resolve()
    assert expanded.filter_args == ()
