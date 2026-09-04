"""Unit tests for Robot keyword-call argument validation."""

from __future__ import annotations

from robot_studio.domain.models.keyword_metadata import (
    KeywordMetadata,
    KeywordSourceType,
    ParameterMetadata,
)
from robot_studio.infrastructure.language.keyword_helpers import (
    validate_keyword_arguments,
)


def _kw(*params: ParameterMetadata, name: str = "Should Be Equal") -> KeywordMetadata:
    return KeywordMetadata(
        name=name,
        source_type=KeywordSourceType.BUILTIN,
        parameters=params,
    )


def test_validate_skips_when_signature_unknown() -> None:
    assert validate_keyword_arguments(_kw(), ["a", "b"]) == []


def test_validate_missing_required() -> None:
    meta = _kw(
        ParameterMetadata(name="first", required=True),
        ParameterMetadata(name="second", required=True),
        ParameterMetadata(name="msg", required=False, default="None"),
    )
    issues = validate_keyword_arguments(meta, ["only-one"])
    codes = [code for code, _ in issues]
    assert codes == ["missing_argument"]
    assert "second" in issues[0][1]


def test_validate_unknown_named_argument() -> None:
    meta = _kw(
        ParameterMetadata(name="message", required=True),
        ParameterMetadata(name="level", required=False, default="INFO"),
        name="Log",
    )
    issues = validate_keyword_arguments(meta, ["hello", "nme=INFO"])
    assert any(code == "unknown_argument" and "nme" in msg for code, msg in issues)


def test_validate_extra_positional() -> None:
    meta = _kw(
        ParameterMetadata(name="path", required=True),
        ParameterMetadata(name="alias", required=False, default="None"),
        name="Open Workbook",
    )
    issues = validate_keyword_arguments(meta, ["a.xlsx", "wb", "extra"])
    assert any(code == "extra_argument" for code, _ in issues)


def test_validate_varargs_absorb_extras() -> None:
    meta = _kw(
        ParameterMetadata(name="items", required=False, kind="var_positional"),
        name="Create List",
    )
    assert validate_keyword_arguments(meta, ["a", "b", "c"]) == []


def test_validate_kwargs_absorb_unknown_named() -> None:
    meta = _kw(
        ParameterMetadata(name="name", required=True),
        ParameterMetadata(name="kwargs", required=False, kind="var_named"),
        name="Create Dictionary",
    )
    assert validate_keyword_arguments(meta, ["name=n", "extra=1"]) == []


def test_validate_create_dictionary_accepts_free_named() -> None:
    """Varargs-only specs treat ``name=value`` as *items, not named args."""
    meta = _kw(
        ParameterMetadata(name="items", required=False, kind="var_positional"),
        name="Create Dictionary",
    )
    assert (
        validate_keyword_arguments(
            meta,
            [
                "id=${KNOWN_POST_ID}",
                "title=updated via put",
                "body=full replacement body",
                "userId=${KNOWN_USER_ID}",
            ],
        )
        == []
    )


def test_validate_varargs_only_create_list_accepts_equals_cells() -> None:
    meta = _kw(
        ParameterMetadata(name="items", required=False, kind="var_positional"),
        name="Create List",
    )
    assert validate_keyword_arguments(meta, ["foo=bar", "a", "b"]) == []


def test_validate_ok_named_and_positional() -> None:
    meta = _kw(
        ParameterMetadata(name="first", required=True),
        ParameterMetadata(name="second", required=True),
        ParameterMetadata(name="msg", required=False, default="None"),
    )
    assert validate_keyword_arguments(meta, ["a", "b", "msg=fail"]) == []


def test_validate_duplicate_named() -> None:
    meta = _kw(
        ParameterMetadata(name="message", required=True),
        name="Log",
    )
    issues = validate_keyword_arguments(meta, ["hello", "message=other"])
    assert any(code == "duplicate_argument" for code, _ in issues)
