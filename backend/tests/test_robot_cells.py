"""Shared Robot Framework cell tokenizer."""

from __future__ import annotations

from robot_studio.infrastructure.language.robot_language_service import (
    RobotLanguageService,
)
from robot_studio.infrastructure.language.robot_parsing_worker import (
    first_robot_cell,
    robot_cell_spans,
    split_robot_cells,
)


def test_split_robot_cells_spaces_tabs_and_mixed() -> None:
    assert split_robot_cells("Log    hello") == ["Log", "hello"]
    assert split_robot_cells("Log\thello") == ["Log", "hello"]
    assert split_robot_cells("Log \thello") == ["Log", "hello"]
    assert split_robot_cells("    Shared Keyword    arg") == ["Shared Keyword", "arg"]


def test_first_robot_cell_does_not_require_four_spaces() -> None:
    assert first_robot_cell("env.py\tencoding=UTF-8") == "env.py"
    assert first_robot_cell("common.resource    WITH NAME    C") == "common.resource"


def test_robot_cell_spans_columns_match_caret() -> None:
    row = "Force Tags    comments    api"
    spans = robot_cell_spans(row)
    names = [token for _start, _end, token in spans]
    assert names == ["Force Tags", "comments", "api"]
    comments_col = row.index("comments") + 1
    assert any(start <= comments_col <= end and token == "comments" for start, end, token in spans)


def test_language_service_uses_shared_spans() -> None:
    content = "*** Test Cases ***\nLogin\n    Shared Keyword    arg\n"
    token = RobotLanguageService._robot_cell_at(content, 3, 8)
    assert token == "Shared Keyword"
    force = "Force Tags    comments    api"
    wrapped = f"*** Settings ***\n{force}\n"
    comments_col = force.index("comments") + 1
    assert RobotLanguageService._is_tag_value_at(wrapped, 2, comments_col)
