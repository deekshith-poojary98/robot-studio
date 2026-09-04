"""Shared helpers for keyword call / parameter authoring (typed models only)."""

from __future__ import annotations

import re

from robot_studio.domain.models.keyword_metadata import (
    KeywordMetadata,
    ParameterMetadata,
)

# Prefer these names when ranking named-arg completions for common keywords.
_POPULAR_PARAM_NAMES: dict[str, tuple[str, ...]] = {
    "open browser": ("url", "browser", "alias"),
    "create dictionary": ("items",),
    "set variable": ("values",),
    "log": ("message", "level"),
    "should be equal": ("first", "second", "msg"),
    "run keyword": ("name",),
    "wait until keyword succeeds": ("retry", "retry_interval", "name"),
}


def strip_keyword_qualifier(keyword: str) -> str:
    """``BuiltIn.Log`` / ``Alias.Open Browser`` → bare keyword name."""
    raw = (keyword or "").strip()
    if "." not in raw:
        return raw
    # Keep multi-word after first dotted library/alias segment.
    head, _, rest = raw.partition(".")
    if rest and not head.startswith(("$", "@", "&", "%")):
        return rest.strip() or raw
    return raw


def parse_argument_cell(cell: str) -> tuple[str | None, str]:
    """Return ``(name, value)`` for ``name=value`` cells; name is None if positional."""
    text = (cell or "").strip()
    if not text or "=" not in text:
        return None, text
    # Robot named args: name=value — name cannot contain spaces typically, but
    # allow ``${var}=`` assignments separately (treated as positional/assign).
    if re.match(r"^[\$@&%]", text):
        return None, text
    name, _, value = text.partition("=")
    name = name.strip()
    if not name or " " in name:
        return None, text
    return name, value


def is_typing_argument_value(cell: str) -> bool:
    """True when [cell] is a value, not a bare ``name`` / empty next-arg slot."""
    text = (cell or "").strip()
    if not text:
        return False
    name, _value = parse_argument_cell(text)
    if name is not None:
        return True
    return re.fullmatch(r"[A-Za-z_][\w]*", text) is None


def present_named_args(arguments: list[str]) -> set[str]:
    """Casefolded names already supplied as ``name=…``."""
    found: set[str] = set()
    for cell in arguments:
        name, _ = parse_argument_cell(cell)
        if name:
            found.add(name.casefold())
    return found


_VARARG_KINDS = frozenset({"var_positional", "var_named", "free_named"})
_POSITIONAL_KINDS = frozenset({"positional_only", "positional_or_named", ""})


def validate_keyword_arguments(
    metadata: KeywordMetadata,
    arguments: list[str],
) -> list[tuple[str, str]]:
    """Return ``(code, message)`` issues for a keyword call.

    Only runs when *metadata* has a real signature (non-empty parameters).
    Unknown signatures are skipped so incomplete libdoc/index rows do not
    produce false extras. Codes: ``unknown_argument``, ``missing_argument``,
    ``extra_argument``, ``duplicate_argument``, ``positional_after_named``.
    """
    params = [p for p in metadata.parameters if (p.name or "").strip()]
    if not params:
        return []

    keyword = metadata.name or "keyword"
    has_var_pos = any(p.kind == "var_positional" for p in params)
    has_var_named = any(p.kind in {"var_named", "free_named"} for p in params)
    bindable = [p for p in params if p.kind not in _VARARG_KINDS]
    # RF only treats ``name=value`` as a named argument when the spec has
    # named slots or ``**kwargs``. Varargs-only keywords (Create Dictionary,
    # Create List, Set Variable) pack those cells into *items as positionals.
    recognize_named = bool(bindable or has_var_named)
    by_name = {p.name.casefold(): p for p in bindable}
    pos_order = [p for p in bindable if p.kind in _POSITIONAL_KINDS]

    bound: set[str] = set()
    issues: list[tuple[str, str]] = []
    saw_named = False
    extra_positional = 0

    for cell in arguments:
        text = (cell or "").strip()
        if not text:
            continue
        name, _value = parse_argument_cell(text)
        if name and recognize_named:
            saw_named = True
            key = name.casefold()
            if key in bound:
                issues.append(
                    (
                        "duplicate_argument",
                        f"Multiple values for argument '{name}' in '{keyword}'",
                    ),
                )
                continue
            if key in by_name:
                bound.add(key)
                continue
            if has_var_named:
                continue
            issues.append(
                (
                    "unknown_argument",
                    f"Unknown argument '{name}' for keyword '{keyword}'",
                ),
            )
            continue
        if saw_named:
            issues.append(
                (
                    "positional_after_named",
                    f"Positional argument after named argument in '{keyword}'",
                ),
            )
            continue
        slot = next((p for p in pos_order if p.name.casefold() not in bound), None)
        if slot is not None:
            bound.add(slot.name.casefold())
            continue
        if has_var_pos:
            continue
        extra_positional += 1

    if extra_positional:
        noun = "argument" if extra_positional == 1 else "arguments"
        issues.append(
            (
                "extra_argument",
                f"Keyword '{keyword}' got {extra_positional} extra {noun}",
            ),
        )

    for param in bindable:
        if param.required and param.name.casefold() not in bound:
            issues.append(
                (
                    "missing_argument",
                    f"Keyword '{keyword}' missing argument '{param.name}'",
                ),
            )
    return issues


def active_parameter_index(
    metadata: KeywordMetadata,
    *,
    arguments: list[str],
    active_hint: int = 0,
    typing_prefix: str = "",
) -> int:
    """
    Resolve which parameter is active given present cells + caret hint.

    Named ``name=`` cells bind by name; positional cells consume remaining
    required/positional slots in order.
    """
    params = list(metadata.parameters)
    if not params:
        return 0

    by_name = {p.name.casefold(): i for i, p in enumerate(params)}
    used: set[int] = set()
    positional_cursor = 0

    for cell in arguments:
        name, _ = parse_argument_cell(cell)
        if name and name.casefold() in by_name:
            used.add(by_name[name.casefold()])
            continue
        # Skip varargs sink for simple positional advance among non-var params
        while positional_cursor < len(params) and (
            positional_cursor in used
            or params[positional_cursor].kind
            in {"var_positional", "var_named", "named_only"}
        ):
            if params[positional_cursor].kind == "named_only":
                positional_cursor += 1
                continue
            if params[positional_cursor].kind in {"var_positional", "var_named"}:
                break
            positional_cursor += 1
        if positional_cursor < len(params):
            used.add(positional_cursor)
            if params[positional_cursor].kind not in {"var_positional", "var_named"}:
                positional_cursor += 1

    # If currently typing name=, highlight that parameter
    typing_name, _ = parse_argument_cell(typing_prefix)
    if typing_name and typing_name.casefold() in by_name:
        return by_name[typing_name.casefold()]

    hint = max(0, active_hint)
    if hint < len(params) and hint not in used:
        return hint

    for index, _param in enumerate(params):
        if index not in used:
            return index
    return min(hint, len(params) - 1)


def parameter_completion_score(
    param: ParameterMetadata,
    *,
    keyword_name: str,
    prefix: str = "",
) -> float:
    """Higher = better named-arg suggestion order."""
    score = 0.0
    if param.required:
        score += 40.0
    else:
        score += 10.0
    if param.default is None:
        score += 5.0
    if param.kind in {"var_positional", "var_named"}:
        score -= 20.0
    if param.kind == "named_only":
        score += 2.0

    popular = _POPULAR_PARAM_NAMES.get(keyword_name.casefold(), ())
    for rank, name in enumerate(popular):
        if param.name.casefold() == name.casefold():
            score += 30.0 - rank * 3.0
            break

    if prefix:
        needle = prefix.rstrip("=").casefold()
        hay = param.name.casefold()
        if hay == needle:
            score += 50.0
        elif hay.startswith(needle):
            score += 25.0

    return score


def parameters_from_detail_string(detail: str) -> tuple[ParameterMetadata, ...]:
    """Best-effort parse of comma-separated argument detail from the index."""
    if not detail:
        return ()
    params: list[ParameterMetadata] = []
    for part in detail.split(","):
        arg = part.strip()
        if not arg:
            continue
        default: str | None = None
        label = arg
        if "=" in arg:
            left, _, right = arg.partition("=")
            label = left.strip()
            default = right.strip()
        name = label.split(":", 1)[0].strip()
        type_name = ""
        if ":" in label:
            type_name = label.split(":", 1)[1].strip()
        params.append(
            ParameterMetadata(
                name=name,
                label=arg,
                default=default,
                required=default is None,
                type_name=type_name,
            ),
        )
    return tuple(params)
