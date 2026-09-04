"""Robot Framework parsing worker — run inside the active workspace venv.

Reads a JSON request from stdin and writes a JSON response to stdout.
Uses robot.api.parsing / get_model as the single parsing source of truth.
"""

from __future__ import annotations

import json
import re
import sys
import tempfile
from pathlib import Path
from typing import Any


def _line_col_at_offset(text: str, offset: int) -> tuple[int, int]:
    offset = max(offset, 0)
    line = text.count("\n", 0, offset) + 1
    last_nl = text.rfind("\n", 0, offset)
    col = offset - last_nl if last_nl >= 0 else offset + 1
    return line, col


def _offset_at_line_col(text: str, line: int, column: int) -> int:
    lines = text.splitlines(keepends=True)
    line = max(line, 1)
    if line > len(lines):
        return len(text)
    offset = sum(len(lines[i]) for i in range(line - 1))
    line_text = lines[line - 1]
    content_len = len(line_text.rstrip("\n\r"))
    col_index = max(0, min(column - 1, content_len))
    return offset + col_index


def _word_at(text: str, line: int, column: int) -> str:
    lines = text.splitlines()
    if line < 1 or line > len(lines):
        return ""
    row = lines[line - 1]
    col = max(0, min(column - 1, len(row)))
    before = row[:col]
    # 2+ spaces / tabs are cell separators. Do not treat ``random    name``
    # as one prefix — that hides ``namespace=`` when the user typed ``name``.
    cells = re.split(r"[ \t]{2,}|\t+", before.lstrip())
    if len(cells) > 1:
        return cells[-1].strip()
    match = re.search(r"[\w${}@&][\w\s${}@&.-]*$", before)
    return match.group(0).strip() if match else ""


def _get_model(content: str):
    from robot.api import get_model

    return get_model(source=content)


def _line_number(node: Any) -> int:
    return int(getattr(node, "lineno", None) or getattr(node, "line", None) or 1)


def _section_label(section: Any) -> str:
    header = section.header
    if header is None:
        return ""
    for token in getattr(header, "tokens", []) or []:
        value = str(getattr(token, "value", "") or "")
        if value.startswith("***") and value.endswith("***"):
            label = value.strip("*").strip().lower()
            return {
                "test case": "test cases",
                "task": "tasks",
            }.get(label, label)
    label = str(header).lower()
    return {
        "test case": "test cases",
        "task": "tasks",
    }.get(label, label)


def _node_name(item: Any) -> str:
    name = getattr(item, "name", None)
    if name is not None:
        return str(name).strip()
    return ""


_VAR_TOKEN_RE = re.compile(r"^([\$@&%]\{[^}]+\})")


def _normalize_var_name(raw: Any) -> str:
    """Strip trailing ``=`` / defaults so ``${x}=`` and ``${p}=secret`` → ``${x}`` / ``${p}``."""
    text = str(raw or "").strip()
    if not text:
        return ""
    match = _VAR_TOKEN_RE.match(text)
    return match.group(1) if match else text


def _variable_symbol(name: str, *, line: int, detail: str) -> dict[str, Any] | None:
    cleaned = _normalize_var_name(name)
    if not cleaned.startswith(("${", "@{", "&{", "%{")):
        return None
    return {
        "name": cleaned,
        "kind": "variable",
        "line": line,
        "detail": detail,
    }


def _collect_body_variables(entries: Any) -> list[dict[str, Any]]:
    """User-declared variables outside ``*** Variables ***`` (VAR, assign, args, FOR)."""
    symbols: list[dict[str, Any]] = []
    for entry in entries or ():
        item_type = type(entry).__name__
        line = _line_number(entry)
        if item_type == "Arguments":
            for cell in getattr(entry, "values", ()) or ():
                symbol = _variable_symbol(cell, line=line, detail="Argument")
                if symbol is not None:
                    symbols.append(symbol)
        elif item_type == "Var":
            symbol = _variable_symbol(
                _node_name(entry) or getattr(entry, "name", ""),
                line=line,
                detail="VAR",
            )
            if symbol is not None:
                symbols.append(symbol)
        elif item_type == "KeywordCall":
            for cell in getattr(entry, "assign", ()) or ():
                symbol = _variable_symbol(cell, line=line, detail="Assignment")
                if symbol is not None:
                    symbols.append(symbol)
        elif item_type == "For":
            assigns = getattr(entry, "assign", None)
            if assigns is None:
                assigns = getattr(entry, "variables", ()) or ()
            for cell in assigns:
                symbol = _variable_symbol(cell, line=line, detail="FOR")
                if symbol is not None:
                    symbols.append(symbol)
            symbols.extend(_collect_body_variables(getattr(entry, "body", None)))
        elif item_type in {"While", "Group", "Else", "Except", "Finally"}:
            symbols.extend(_collect_body_variables(getattr(entry, "body", None)))
        elif item_type in {"If", "ElseIf"}:
            symbols.extend(_collect_body_variables(getattr(entry, "body", None)))
            if item_type == "If":
                for branch in getattr(entry, "orelse", None) or ():
                    symbols.extend(_collect_body_variables([branch]))
        elif item_type == "Try":
            symbols.extend(_collect_body_variables(getattr(entry, "body", None)))
            for branch in getattr(entry, "except_branches", None) or ():
                symbols.extend(_collect_body_variables([branch]))
            symbols.extend(
                _collect_body_variables(getattr(entry, "finally_body", None)),
            )
    return symbols


def parse_diagnostics(content: str, file_path: str) -> list[dict[str, Any]]:
    _ = file_path
    model = _get_model(content)
    diagnostics: list[dict[str, Any]] = []
    for err in model.errors:
        diagnostics.append(
            {
                "severity": "error",
                "line": int(getattr(err, "lineno", None) or 1),
                "column": int(getattr(err, "col", None) or 1),
                "message": str(getattr(err, "message", err)),
                "source": "robot.parser",
            },
        )

    seen_keywords: dict[str, int] = {}
    seen_variables: dict[str, int] = {}
    for section in model.sections:
        header = _section_label(section)
        for item in section.body:
            item_type = type(item).__name__
            if item_type == "Keyword":
                name = _node_name(item)
                if name:
                    if name.lower() in seen_keywords:
                        diagnostics.append(
                            {
                                "severity": "warning",
                                "line": _line_number(item),
                                "column": 1,
                                "message": f"Duplicate keyword '{name}'",
                                "source": "robot.semantic",
                            },
                        )
                    seen_keywords[name.lower()] = _line_number(item)
            if item_type == "Variable":
                name = _node_name(item)
                if name:
                    if name in seen_variables:
                        diagnostics.append(
                            {
                                "severity": "warning",
                                "line": _line_number(item),
                                "column": 1,
                                "message": f"Duplicate variable '{name}'",
                                "source": "robot.semantic",
                            },
                        )
                    seen_variables[name] = _line_number(item)
            if header in {"test cases", "tasks"} and item_type == "TestCase":
                testcase_name = _node_name(item)
                if testcase_name:
                    key = testcase_name.lower()
                    if key in seen_keywords:
                        diagnostics.append(
                            {
                                "severity": "warning",
                                "line": _line_number(item),
                                "column": 1,
                                "message": f"Duplicate test case '{testcase_name}'",
                                "source": "robot.semantic",
                            },
                        )
                    seen_keywords[key] = _line_number(item)

    return diagnostics


def _collect_documentation(item: Any) -> str:
    docs: list[str] = []
    body = getattr(item, "body", None) or []
    for entry in body:
        if type(entry).__name__ != "Documentation":
            continue
        value = getattr(entry, "value", None)
        if value:
            docs.append(str(value))
            continue
        values = getattr(entry, "values", None) or []
        if values:
            docs.append(" ".join(str(value) for value in values))
    return "\n".join(docs).strip()


def _collect_arguments(item: Any) -> list[str]:
    """Return ``[Arguments]`` cells for a Keyword / user-keyword node."""
    body = getattr(item, "body", None) or []
    for entry in body:
        if type(entry).__name__ != "Arguments":
            continue
        values = getattr(entry, "values", None) or ()
        return [str(value).strip() for value in values if str(value).strip()]
    return []


def _arguments_detail(item: Any) -> str:
    """Comma-separated argument labels for index / hover / signature help."""
    return ", ".join(_collect_arguments(item))


def _end_line(node: Any) -> int:
    end = getattr(node, "end_lineno", None)
    if end is not None:
        return int(end)
    # Fall back: deepest child end / self line.
    deepest = _line_number(node)
    for attr in ("body", "orelse", "except_branches", "finally_body", "try_body"):
        children = getattr(node, attr, None) or ()
        for child in children:
            deepest = max(deepest, _end_line(child))
    return deepest


def _column(node: Any) -> int:
    return int(getattr(node, "col_offset", None) or getattr(node, "col", None) or 1)


def _node(
    *,
    name: str,
    kind: str,
    line: int,
    end_line: int | None = None,
    column: int = 1,
    detail: str = "",
    documentation: str = "",
    children: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    end = end_line if end_line is not None else line
    return {
        "name": name,
        "kind": kind,
        "line": line,
        "end_line": end,
        "column": column,
        "detail": detail,
        "documentation": documentation,
        "children": children or [],
        "id": f"{kind}:{line}:{name}",
    }


_SECTION_TITLES = {
    "settings": "Settings",
    "variables": "Variables",
    "keywords": "Keywords",
    "test cases": "Tests",
    "tasks": "Tasks",
    "comments": "Comments",
}

_CONTROL_LABELS = {
    "If": "IF",
    "ElseIf": "ELSE IF",
    "Else": "ELSE",
    "For": "FOR",
    "While": "WHILE",
    "Try": "TRY",
    "Except": "EXCEPT",
    "Finally": "FINALLY",
    "Break": "BREAK",
    "Continue": "CONTINUE",
    "ReturnStatement": "RETURN",
    "ReturnSetting": "RETURN",
    "Var": "VAR",
}


def _walk_body(entries: Any) -> list[dict[str, Any]]:
    """Nested symbols for keyword/test bodies (calls + control structures)."""
    nodes: list[dict[str, Any]] = []
    for entry in entries or ():
        item_type = type(entry).__name__
        line = _line_number(entry)
        end = _end_line(entry)
        col = _column(entry)
        if item_type == "KeywordCall":
            name = str(getattr(entry, "keyword", "") or "").strip()
            if not name:
                continue
            nodes.append(
                _node(
                    name=name,
                    kind="keyword_call",
                    line=line,
                    end_line=end,
                    column=col,
                    detail="Call",
                ),
            )
        elif item_type in _CONTROL_LABELS:
            label = _CONTROL_LABELS[item_type]
            title = label
            if item_type == "For":
                variables = "  ".join(
                    str(v) for v in (getattr(entry, "assign", None) or ())
                )
                values = "  ".join(
                    str(v) for v in (getattr(entry, "values", None) or ())
                )
                if variables or values:
                    title = f"FOR  {variables}  IN  {values}".strip()
            elif item_type == "While":
                condition = str(getattr(entry, "condition", "") or "").strip()
                if condition:
                    title = f"WHILE  {condition}"
            elif item_type in {"If", "ElseIf"}:
                condition = str(getattr(entry, "condition", "") or "").strip()
                if condition:
                    title = f"{label}  {condition}"
            elif item_type == "Var":
                title = _node_name(entry) or "VAR"
            children = _walk_body(getattr(entry, "body", None))
            # If / Try nest branches as siblings under the control node.
            if item_type == "If":
                for branch in getattr(entry, "orelse", None) or ():
                    children.extend(_walk_body([branch]))
            if item_type == "Try":
                for branch in getattr(entry, "except_branches", None) or ():
                    children.extend(_walk_body([branch]))
                finally_body = getattr(entry, "finally_body", None) or ()
                if finally_body:
                    children.append(
                        _node(
                            name="FINALLY",
                            kind="control",
                            line=_line_number(finally_body[0])
                            if finally_body
                            else line,
                            end_line=_end_line(finally_body[-1])
                            if finally_body
                            else end,
                            children=_walk_body(finally_body),
                        ),
                    )
            nodes.append(
                _node(
                    name=title,
                    kind="variable" if item_type == "Var" else "control",
                    line=line,
                    end_line=end,
                    column=col,
                    detail=label,
                    children=children,
                ),
            )
        elif item_type in {"Setup", "Teardown", "Template"}:
            label = item_type
            name = _node_name(entry) or label
            nodes.append(
                _node(
                    name=name,
                    kind="setting",
                    line=line,
                    end_line=end,
                    column=col,
                    detail=label,
                ),
            )
        elif item_type == "Tags":
            for tag in getattr(entry, "values", ()) or ():
                nodes.append(
                    _node(
                        name=str(tag),
                        kind="tag",
                        line=line,
                        end_line=end,
                        column=col,
                        detail="Tags",
                    ),
                )
        # Documentation is kept on the parent keyword/test via
        # `_collect_documentation` — do not mirror it as an outline child.
    return nodes


def _settings_child(item: Any) -> dict[str, Any] | None:
    item_type = type(item).__name__
    line = _line_number(item)
    end = _end_line(item)
    col = _column(item)
    if item_type == "LibraryImport":
        return _node(
            name=_node_name(item),
            kind="library",
            line=line,
            end_line=end,
            column=col,
            detail="Library",
        )
    if item_type == "ResourceImport":
        return _node(
            name=_node_name(item),
            kind="resource",
            line=line,
            end_line=end,
            column=col,
            detail="Resource",
        )
    if item_type == "VariablesImport":
        return _node(
            name=_node_name(item),
            kind="resource",
            line=line,
            end_line=end,
            column=col,
            detail="Variables",
        )
    if item_type == "Documentation":
        # Suite Documentation stays on the suite/file metadata; outline only
        # lists actionable Settings (imports, setup/teardown, tags, …).
        return None
    if item_type in {"TestTags", "DefaultTags", "ForceTags"}:
        detail = {
            "TestTags": "Test Tags",
            "DefaultTags": "Default Tags",
            "ForceTags": "Force Tags",
        }.get(item_type, item_type)
        children = [
            _node(name=str(tag), kind="tag", line=line, end_line=end, detail=detail)
            for tag in (getattr(item, "values", ()) or ())
        ]
        return _node(
            name=detail,
            kind="setting",
            line=line,
            end_line=end,
            column=col,
            detail=detail,
            children=children,
        )
    if item_type in {
        "SuiteSetup",
        "SuiteTeardown",
        "TestSetup",
        "TestTeardown",
        "TestTimeout",
        "TaskTimeout",
        "Metadata",
    }:
        label = {
            "SuiteSetup": "Suite Setup",
            "SuiteTeardown": "Suite Teardown",
            "TestSetup": "Test Setup",
            "TestTeardown": "Test Teardown",
            "TestTimeout": "Test Timeout",
            "TaskTimeout": "Task Timeout",
            "Metadata": "Metadata",
        }.get(item_type, item_type)
        return _node(
            name=_node_name(item) or label,
            kind="setting",
            line=line,
            end_line=end,
            column=col,
            detail=label,
        )
    return None


def document_symbol_tree(content: str, file_path: str) -> dict[str, Any]:
    """Build a nested DocumentSymbolTree payload for document intelligence."""
    path = file_path or "file.robot"
    suffix = Path(path).suffix.lower()
    if suffix == ".py":
        from robot_studio.infrastructure.language.python_document_symbols import (
            python_document_symbol_tree,
        )

        return python_document_symbol_tree(content, path)

    model = _get_model(content)
    stem = Path(path).stem
    root_kind = "resource" if suffix == ".resource" else "test_suite"
    root_name = stem or Path(path).name

    section_nodes: list[dict[str, Any]] = []
    for section in model.sections:
        header = _section_label(section)
        title = _SECTION_TITLES.get(header)
        if not title:
            continue
        section_line = _line_number(getattr(section, "header", None) or section)
        section_end = _end_line(section)
        children: list[dict[str, Any]] = []

        for item in section.body:
            item_type = type(item).__name__
            line = _line_number(item)
            end = _end_line(item)
            col = _column(item)

            if header == "settings":
                child = _settings_child(item)
                if child is not None:
                    children.append(child)
            elif header == "variables" and item_type == "Variable":
                children.append(
                    _node(
                        name=_node_name(item),
                        kind="variable",
                        line=line,
                        end_line=end,
                        column=col,
                    ),
                )
            elif header == "keywords" and item_type == "Keyword":
                children.append(
                    _node(
                        name=_node_name(item),
                        kind="keyword",
                        line=line,
                        end_line=end,
                        column=col,
                        detail=_arguments_detail(item),
                        documentation=_collect_documentation(item),
                        children=_walk_body(getattr(item, "body", None)),
                    ),
                )
            elif header in {"test cases", "tasks"} and item_type == "TestCase":
                children.append(
                    _node(
                        name=_node_name(item),
                        kind="test_case",
                        line=line,
                        end_line=end,
                        column=col,
                        detail=title,
                        documentation=_collect_documentation(item),
                        children=_walk_body(getattr(item, "body", None)),
                    ),
                )

        if children or title in {"Settings", "Variables", "Keywords", "Tests", "Tasks"}:
            section_nodes.append(
                _node(
                    name=title,
                    kind="section",
                    line=section_line,
                    end_line=section_end,
                    detail=header,
                    children=children,
                ),
            )

    root_end = max((n["end_line"] for n in section_nodes), default=1)
    root = _node(
        name=root_name,
        kind=root_kind,
        line=1,
        end_line=root_end,
        detail=Path(path).name,
        children=section_nodes,
    )
    return {
        "file_path": path,
        "root": root,
    }


def document_symbols(content: str, file_path: str) -> list[dict[str, Any]]:
    path = file_path or "file.robot"
    model = _get_model(content)
    symbols: list[dict[str, Any]] = []
    suffix = Path(path).suffix.lower()

    symbols.append(
        {
            "name": Path(path).name,
            "kind": "file",
            "line": 1,
            "detail": suffix.lstrip("."),
        },
    )
    if suffix == ".robot":
        symbols.append(
            {"name": Path(path).stem, "kind": "test_suite", "line": 1, "detail": ""},
        )
    elif suffix == ".resource":
        symbols.append(
            {"name": Path(path).stem, "kind": "resource", "line": 1, "detail": ""},
        )

    for section in model.sections:
        header = _section_label(section)
        for item in section.body:
            item_type = type(item).__name__
            line = _line_number(item)
            if item_type == "LibraryImport":
                symbols.append(
                    {
                        "name": _node_name(item),
                        "kind": "library",
                        "line": line,
                        "detail": "Library",
                    },
                )
            elif item_type == "ResourceImport":
                symbols.append(
                    {
                        "name": _node_name(item),
                        "kind": "resource",
                        "line": line,
                        "detail": "Resource",
                    },
                )
            elif item_type == "Documentation":
                # Documentation text is attached to keywords/tests/suite metadata;
                # do not index the first word of the doc as its own symbol.
                continue
            elif item_type in {"TestTags", "DefaultTags", "ForceTags"}:
                detail = {
                    "TestTags": "Test Tags",
                    "DefaultTags": "Default Tags",
                    "ForceTags": "Force Tags",
                }.get(item_type, item_type)
                for tag in getattr(item, "values", ()) or ():
                    symbols.append(
                        {
                            "name": str(tag),
                            "kind": "tag",
                            "line": line,
                            "detail": detail,
                        },
                    )
            elif item_type in {
                "SuiteSetup",
                "SuiteTeardown",
                "TestSetup",
                "TestTeardown",
            }:
                label = {
                    "SuiteSetup": "Suite Setup",
                    "SuiteTeardown": "Suite Teardown",
                    "TestSetup": "Test Setup",
                    "TestTeardown": "Test Teardown",
                }[item_type]
                symbols.append(
                    {
                        "name": _node_name(item) or label,
                        "kind": "setting",
                        "line": line,
                        "detail": label,
                    },
                )
            elif item_type == "Variable":
                symbols.append(
                    {
                        "name": _node_name(item),
                        "kind": "variable",
                        "line": line,
                        "detail": "Variables",
                    },
                )
            elif item_type == "Keyword":
                symbols.append(
                    {
                        "name": _node_name(item),
                        "kind": "keyword",
                        "line": line,
                        "detail": _arguments_detail(item),
                        "documentation": _collect_documentation(item),
                    },
                )
                symbols.extend(
                    _collect_body_variables(getattr(item, "body", None)),
                )
            elif item_type == "TestCase":
                kind = "test_case" if header in {"test cases", "tasks"} else "keyword"
                case_name = _node_name(item)
                case_tags: list[str] = []
                case_setup: str | None = None
                case_teardown: str | None = None
                for entry in getattr(item, "body", []) or []:
                    entry_type = type(entry).__name__
                    if entry_type == "Tags":
                        case_tags.extend(
                            str(tag) for tag in (getattr(entry, "values", ()) or ())
                        )
                    elif entry_type == "Setup":
                        case_setup = _node_name(entry) or "Setup"
                    elif entry_type == "Teardown":
                        case_teardown = _node_name(entry) or "Teardown"
                detail = {
                    "test cases": "test case",
                    "tasks": "task",
                }.get(header, header)
                if case_tags:
                    detail = f"{detail}|tags:{','.join(case_tags)}"
                symbols.append(
                    {
                        "name": case_name,
                        "kind": kind,
                        "line": line,
                        "detail": detail,
                        "documentation": _collect_documentation(item),
                    },
                )
                symbols.extend(
                    _collect_body_variables(getattr(item, "body", None)),
                )
                for tag in case_tags:
                    symbols.append(
                        {
                            "name": str(tag),
                            "kind": "tag",
                            "line": line,
                            "detail": f"test:{case_name}",
                        },
                    )
                if case_setup:
                    symbols.append(
                        {
                            "name": case_setup,
                            "kind": "setting",
                            "line": line,
                            "detail": f"Setup:{case_name}",
                        },
                    )
                if case_teardown:
                    symbols.append(
                        {
                            "name": case_teardown,
                            "kind": "setting",
                            "line": line,
                            "detail": f"Teardown:{case_name}",
                        },
                    )
    return symbols


def extract_settings_import_paths(content: str) -> list[str]:
    """Path tokens from ``Resource`` and ``Variables`` settings (not ``Library``)."""
    model = _get_model(content)
    paths: list[str] = []
    for section in model.sections:
        for item in getattr(section, "body", ()) or ():
            item_type = type(item).__name__
            if item_type not in {"ResourceImport", "VariablesImport"}:
                continue
            token = _node_name(item)
            if token and "${" not in token:
                paths.append(token)
    return paths


def extract_references(content: str, file_path: str) -> list[dict[str, Any]]:
    path = file_path or "file.robot"
    model = _get_model(content)
    references: list[dict[str, Any]] = []
    for section in model.sections:
        header = _section_label(section)
        if header not in {"test cases", "tasks", "keywords"}:
            continue
        for item in section.body:
            item_type = type(item).__name__
            if item_type not in {"TestCase", "Keyword"}:
                continue
            for entry in getattr(item, "body", []) or []:
                if type(entry).__name__ != "KeywordCall":
                    continue
                keyword = str(getattr(entry, "keyword", "") or "").strip()
                if not keyword:
                    continue
                references.append(
                    {
                        "name": keyword,
                        "file_path": path,
                        "line": _line_number(entry),
                        "context": keyword,
                    },
                )
    return references


def format_document(content: str, file_path: str) -> str:
    path = file_path or "file.robot"
    suffix = Path(path).suffix or ".robot"
    model = _get_model(content)
    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=suffix,
        delete=False,
        encoding="utf-8",
    ) as handle:
        tmp_path = handle.name
    try:
        model.save(tmp_path)
        text = Path(tmp_path).read_text(encoding="utf-8")
    finally:
        Path(tmp_path).unlink(missing_ok=True)
    lines = [line.rstrip() for line in text.splitlines()]
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines) + ("\n" if lines else "")


def completion_context(
    content: str,
    file_path: str,
    line: int,
    column: int,
) -> dict[str, Any]:
    _ = file_path
    lines = content.splitlines()
    if line < 1 or line > len(lines):
        return {"prefix": "", "context": "unknown"}
    row = lines[line - 1]
    stripped = row.strip()
    prefix = _word_at(content, line, column)

    # Comments / documentation setting rows — no completions that invent keywords.
    if stripped.startswith("#"):
        return {"prefix": prefix, "context": "unknown", "section": ""}

    section = "unknown"
    for idx in range(line - 1, -1, -1):
        candidate = lines[idx].strip()
        if candidate.startswith("*") and candidate.endswith("*"):
            section = candidate.strip("*").strip().lower()
            break

    # Local settings: "    [Doc…" inside Test Cases / Keywords / Tasks.
    local_setting = re.match(r"^(\s*)(\[[^\]]*)\]?", row)
    if local_setting and (row.startswith((" ", "\t"))):
        bracket_prefix = local_setting.group(2)
        if bracket_prefix.startswith("["):
            return {
                "prefix": bracket_prefix if column > len(local_setting.group(1)) else prefix,
                "context": "local_setting",
                "section": section,
            }

    if stripped.startswith("***") or (not stripped and prefix.startswith("*")):
        return {"prefix": prefix or stripped, "context": "section", "section": section}

    if stripped.startswith("Library ") or "Library" in stripped[:20]:
        return {"prefix": prefix, "context": "library", "section": section}
    if stripped.startswith("Resource ") or "Resource" in stripped[:20]:
        return {"prefix": prefix, "context": "resource", "section": section}
    if section == "settings":
        # Documentation suite setting — not argument authoring.
        if stripped.lower().startswith("documentation"):
            return {"prefix": prefix, "context": "setting", "section": section}
        return {"prefix": prefix, "context": "setting", "section": section}
    if section == "variables" or prefix.startswith(("${", "@{", "&{")):
        return {"prefix": prefix, "context": "variable", "section": section}
    if section in {"keywords", "test cases", "tasks"}:
        if row.startswith((" ", "\t")):
            call = _keyword_call_at(lines, line, column)
            if call is not None and call.get("in_arguments"):
                return {
                    "prefix": prefix,
                    "context": "argument",
                    "section": section,
                    "keyword": call["keyword"],
                    "arguments": call["arguments"],
                    "active_parameter": call["active_parameter"],
                    "current_argument": call.get("current_argument") or "",
                    "arguments_completed": call.get("arguments_completed") or [],
                }
            return {"prefix": prefix, "context": "keyword_call", "section": section}
        return {"prefix": prefix, "context": "keyword", "section": section}
    return {"prefix": prefix, "context": "keyword_call", "section": section}


def _robot_cells(row: str) -> list[str]:
    """Split a Robot Framework row into cells (2+ spaces or tabs)."""
    return [cell for cell in re.split(r"[ \t]{2,}|\t+", row.strip()) if cell]


def _keyword_call_at(
    lines: list[str],
    line: int,
    column: int,
) -> dict[str, Any] | None:
    """Resolve keyword + args for an indented call (supports ``...`` continuations)."""
    if line < 1 or line > len(lines):
        return None
    row = lines[line - 1]
    if not (row.startswith((" ", "\t"))):
        return None
    if row.strip().startswith("#"):
        return None
    if row.strip().startswith("["):
        return None

    # Walk up through continuation rows to the keyword row.
    start = line - 1
    while start > 0:
        prev = lines[start - 1]
        if not (prev.startswith((" ", "\t"))):
            break
        prev_cells = _robot_cells(prev)
        if prev_cells and prev_cells[0] == "...":
            start -= 1
            continue
        # Current row is continuation — keyword is on previous body row.
        cur_cells = _robot_cells(row)
        if cur_cells and cur_cells[0] == "...":
            start -= 1
            continue
        break

    # Collect cells from keyword row + following continuations up to *line*.
    all_cells: list[str] = []
    keyword = ""
    keyword_index = 0
    for idx in range(start, line):
        cells = _robot_cells(lines[idx])
        if not cells:
            continue
        if cells[0] == "...":
            all_cells.extend(cells[1:])
            continue
        if not keyword:
            keyword_index = 0
            if re.match(r"^[\$@&%]", cells[0]) and len(cells) > 1:
                keyword_index = 1
            if keyword_index >= len(cells):
                return None
            keyword = cells[keyword_index]
            all_cells.extend(cells[keyword_index + 1 :])
        else:
            all_cells.extend(cells)

    if not keyword or keyword == "...":
        return None

    # Active parameter from cells before caret on current row.
    cur = lines[line - 1]
    col_in_row = max(0, min(column - 1, len(cur)))
    before_on_row = _robot_cells(cur[:col_in_row])
    # Args already fully before this row:
    args_before_row: list[str] = []
    for idx in range(start, line - 1):
        cells = _robot_cells(lines[idx])
        if not cells:
            continue
        if cells[0] == "...":
            args_before_row.extend(cells[1:])
            continue
        k_idx = 0
        if re.match(r"^[\$@&%]", cells[0]) and len(cells) > 1:
            k_idx = 1
        args_before_row.extend(cells[k_idx + 1 :])

    if before_on_row and before_on_row[0] == "...":
        args_through_caret = args_before_row + before_on_row[1:]
        in_arguments = True
    else:
        k_idx = 0
        if before_on_row and re.match(r"^[\$@&%]", before_on_row[0]) and len(before_on_row) > 1:
            k_idx = 1
        # Past keyword cell?
        if len(before_on_row) > k_idx + 1 or (
            len(before_on_row) == k_idx + 1
            and col_in_row > 0
            and (cur[:col_in_row].endswith("  ") or cur[:col_in_row].endswith("\t"))
        ):
            in_arguments = True
            args_through_caret = args_before_row + before_on_row[k_idx + 1 :]
        elif len(before_on_row) > k_idx and before_on_row[0] != keyword:
            # Continuation-style body without ...
            in_arguments = len(args_before_row) > 0 or len(before_on_row) > k_idx + 1
            args_through_caret = args_before_row + (
                before_on_row[k_idx + 1 :] if in_arguments else []
            )
        else:
            in_arguments = len(args_before_row) > 0
            args_through_caret = list(args_before_row)

    # Trailing separator after keyword → entering first argument slot.
    if not in_arguments:
        cells_full = _robot_cells(cur)
        k_idx = 0
        if cells_full and re.match(r"^[\$@&%]", cells_full[0]) and len(cells_full) > 1:
            k_idx = 1
        if cells_full and k_idx < len(cells_full):
            # Detect 2+ spaces / tab after the keyword token (ignore leading indent).
            kw_token = cells_full[k_idx]
            indent_match = re.match(r"^[ \t]*", cur)
            indent_len = len(indent_match.group(0)) if indent_match else 0
            body = cur[indent_len:col_in_row]
            # Assignment cell before keyword
            if k_idx == 1 and cells_full:
                # body may start with ${x} then separator then keyword
                pass
            kw_pos = body.find(kw_token)
            if kw_pos >= 0:
                after_kw = body[kw_pos + len(kw_token) :]
                if re.match(r"[ \t]{2,}|\t", after_kw):
                    in_arguments = True
                    args_through_caret = list(args_before_row)

    prefix_text = cur[:col_in_row]
    at_new_slot = bool(re.search(r"(?:[ \t]{2,}|\t)$", prefix_text))
    args_completed = list(args_through_caret)
    current_argument = ""
    if in_arguments and not at_new_slot and args_completed:
        current_argument = args_completed[-1]
        args_completed = args_completed[:-1]
    active = len(args_completed)
    return {
        "keyword": keyword,
        "arguments": all_cells,
        "active_parameter": active,
        "in_arguments": in_arguments,
        "arguments_through_caret": args_through_caret,
        "arguments_completed": args_completed,
        "current_argument": current_argument,
    }


def _robot_cell_spans(row: str) -> list[tuple[str, int, int]]:
    """Return ``(cell, start_col, end_col)`` with 1-based inclusive columns."""
    spans: list[tuple[str, int, int]] = []
    i = 0
    n = len(row)
    while i < n and row[i] in " \t":
        i += 1
    while i < n:
        start = i
        while i < n:
            if row[i] == "\t":
                break
            if row[i] == " " and i + 1 < n and row[i + 1] in " \t":
                break
            i += 1
        cell = row[start:i]
        if cell:
            # Inclusive end column: last character is at index i-1 → col i.
            spans.append((cell, start + 1, i))
        sep = re.match(r"[ \t]{2,}|\t+", row[i:])
        if sep:
            i += len(sep.group(0))
            continue
        break
    return spans


def _looks_like_keyword_token(text: str) -> bool:
    """True for a cell that can name a keyword (not variables / settings / sep)."""
    token = text.strip()
    if not token or token == "...":
        return False
    if token.startswith(("$", "@", "&", "%", "#", "[")):
        return False
    return not token.endswith("=")


def _hover_keyword_at(
    lines: list[str],
    line: int,
    column: int,
) -> dict[str, Any] | None:
    """Keyword under the pointer only — ignores argument / variable cells.

    Supports multiple keyword-like cells on one row (e.g. ``Run Keyword If``
    taking another keyword as an argument): whichever cell the column hits
    is the hover target.
    """
    if line < 1 or line > len(lines):
        return None
    row = lines[line - 1]
    if not (row.startswith((" ", "\t"))):
        return None
    if row.strip().startswith(("#", "[")):
        return None
    for text, start, end in _robot_cell_spans(row):
        if start <= column <= end:
            if not _looks_like_keyword_token(text):
                return None
            return {
                "keyword": text,
                "arguments": [],
                "active_parameter": 0,
                "in_arguments": False,
                "arguments_through_caret": [],
                "arguments_completed": [],
                "current_argument": "",
            }
    return None


def signature_help(
    content: str,
    file_path: str,
    line: int,
    column: int,
    *,
    hover: bool = False,
) -> dict[str, Any] | None:
    _ = file_path
    lines = content.splitlines()
    if line < 1 or line > len(lines):
        return None
    row = lines[line - 1]
    if not (row.startswith((" ", "\t"))):
        return None
    if row.strip().startswith(("#", "[")):
        return None
    if hover:
        return _hover_keyword_at(lines, line, column)
    call = _keyword_call_at(lines, line, column)
    if call is None or not call.get("keyword"):
        return None
    return {
        "keyword": call["keyword"],
        "active_parameter": int(call.get("active_parameter") or 0),
        "arguments": list(call.get("arguments") or []),
        "in_arguments": bool(call.get("in_arguments")),
        "current_argument": str(call.get("current_argument") or ""),
        "arguments_completed": list(call.get("arguments_completed") or []),
    }


def _is_remote_library_name(name: str) -> bool:
    """True for RF's standard Remote library (short or fully-qualified)."""
    folded = name.strip().casefold()
    return folded in {"remote", "robot.libraries.remote"}


def _remote_library_stub(error: str | None = None) -> dict:
    """Remote keywords come from a live XML-RPC server — never treat as missing."""
    payload: dict = {
        "available": True,
        "name": "Remote",
        "doc_format": "ROBOT",
        "keywords": [],
        "keyword_info": {},
        "source_type": "remote",
    }
    if error:
        payload["error"] = error
    return payload


def _libdoc_to_resolve_payload(
    doc: object,
    *,
    default_name: str,
    source_type: str,
) -> dict:
    """Map a Robot ``LibraryDocumentation`` instance to the resolve transport dict."""
    library_name = str(getattr(doc, "name", None) or default_name)
    # ROBOT_LIBRARY_DOC_FORMAT: ROBOT (libdoc's default), MARKDOWN, HTML,
    # TEXT or REST. The renderer needs it to pick the right markup dialect.
    doc_format = str(getattr(doc, "doc_format", "") or "").upper()
    keywords: list[str] = []
    keyword_info: dict[str, dict] = {}
    for kw in getattr(doc, "keywords", []) or []:
        kw_name = str(kw.name)
        keywords.append(kw_name)
        parameters: list[dict] = []
        for arg in getattr(kw, "args", []) or []:
            parameters.append(_arginfo_to_transport(arg))
        tags = tuple(str(t) for t in (getattr(kw, "tags", None) or []))
        deprecated = bool(getattr(kw, "deprecated", False))
        keyword_info[kw_name.casefold()] = {
            "name": kw_name,
            "qualified_name": f"{library_name}.{kw_name}",
            "source_type": source_type,
            "library_name": library_name,
            "documentation": str(
                getattr(kw, "doc", None)
                or getattr(kw, "short_doc", None)
                or "",
            ),
            "doc_format": doc_format,
            "parameters": parameters,
            "source_path": str(getattr(doc, "source", None) or ""),
            "source_line": getattr(kw, "lineno", None),
            "deprecated": deprecated,
            "tags": list(tags),
            "examples": [],
            "detail": ", ".join(
                str(p.get("label") or p.get("name") or "") for p in parameters
            ),
        }
    return {
        "available": True,
        "name": library_name,
        "doc_format": doc_format,
        "keywords": keywords,
        "keyword_info": keyword_info,
        "source_type": source_type,
    }


def resolve_library(name: str, file_path: str = "") -> dict:
    """Resolve a Library import against this environment via Robot libdoc."""
    cleaned = (name or "").strip()
    if not cleaned:
        return {"available": False, "name": "", "keywords": [], "keyword_info": {}}
    # Path-style imports are relative to the importing suite (Robot's rule).
    if file_path and (
        cleaned.endswith((".py", ".robot", ".resource"))
        or "/" in cleaned
        or "\\" in cleaned
        or cleaned.startswith(".")
    ):
        candidate = Path(cleaned).expanduser()
        if not candidate.is_file():
            beside = (Path(file_path).expanduser().resolve().parent / cleaned).resolve()
            if beside.is_file():
                cleaned = str(beside)
        else:
            cleaned = str(candidate.resolve())
    try:
        from robot.libdoc import LibraryDocumentation

        # Remote is a standard RF library, but libdoc calls get_keyword_names()
        # which connects to the remote server. Use a short timeout, and if the
        # server is down still report the library as available (not missing).
        if _is_remote_library_name(cleaned):
            try:
                doc = LibraryDocumentation(
                    cleaned,
                    "http://127.0.0.1:8270",
                    "1 second",
                )
            except Exception as exc:  # noqa: BLE001 — connection / import failures
                try:
                    __import__("robot.libraries.Remote")
                except ImportError:
                    return {
                        "available": False,
                        "name": cleaned,
                        "keywords": [],
                        "keyword_info": {},
                        "error": str(exc),
                    }
                return _remote_library_stub(str(exc))
            return _libdoc_to_resolve_payload(
                doc,
                default_name="Remote",
                source_type="remote",
            )

        doc = LibraryDocumentation(cleaned)
        library_name = str(doc.name or cleaned)
        source_type = "builtin" if library_name.casefold() == "builtin" else "library"
        return _libdoc_to_resolve_payload(
            doc,
            default_name=cleaned,
            source_type=source_type,
        )
    except Exception as exc:  # noqa: BLE001 — import / libdoc failures
        return {
            "available": False,
            "name": cleaned,
            "keywords": [],
            "keyword_info": {},
            "error": str(exc),
        }


def _arginfo_to_transport(arg: object) -> dict:
    """Map Robot ArgInfo → transport dict for ParameterMetadata.from_transport."""
    name = str(getattr(arg, "name", None) or str(arg)).strip()
    default = getattr(arg, "default", None)
    # robot.running.arguments.ArgumentSpec uses NOT_SET sentinel
    default_str: str | None
    if default is None or str(default) in {"NOT_SET", "<class 'robot.utils.notset.NotSet'>"}:
        default_str = None
    else:
        try:
            from robot.utils import NOT_SET

            if default is NOT_SET:
                default_str = None
            else:
                default_str = str(default)
        except Exception:  # noqa: BLE001
            default_str = str(default) if default is not None else None

    kind_obj = getattr(arg, "kind", None)
    kind = str(getattr(kind_obj, "name", None) or kind_obj or "positional_or_named")
    kind = kind.lower()
    type_obj = getattr(arg, "type", None) or getattr(arg, "types", None)
    type_name = ""
    if type_obj is not None:
        type_name = str(type_obj)
    required = bool(getattr(arg, "required", default_str is None))
    if kind in {"var_positional", "var_named", "free_named"}:
        required = False
    label = str(arg)
    # Prefer structured name when label is the full ArgInfo repr
    if not name or name == label:
        name = label.split("=", 1)[0].split(":", 1)[0].strip()
    return {
        "name": name,
        "label": label,
        "default": default_str,
        "required": required,
        "kind": kind,
        "type_name": type_name,
        "documentation": "",
    }


def main() -> None:
    request = json.load(sys.stdin)
    op = request.get("op")
    content = str(request.get("content") or "")
    file_path = str(request.get("file_path") or "")
    line = int(request.get("line") or 1)
    column = int(request.get("column") or 1)
    library = str(request.get("library") or "")

    try:
        if op == "diagnostics":
            result = parse_diagnostics(content, file_path)
        elif op == "document_symbols":
            result = document_symbols(content, file_path)
        elif op == "document_symbol_tree":
            result = document_symbol_tree(content, file_path)
        elif op == "format":
            result = format_document(content, file_path)
        elif op == "completion_context":
            result = completion_context(content, file_path, line, column)
        elif op == "signature_help":
            result = signature_help(
                content,
                file_path,
                line,
                column,
                hover=bool(request.get("hover")),
            )
        elif op == "resolve_library":
            result = resolve_library(library, file_path)
        else:
            raise ValueError(f"Unknown op: {op}")
        json.dump({"ok": True, "result": result}, sys.stdout)
    except Exception as exc:  # noqa: BLE001 — worker boundary
        json.dump({"ok": False, "error": str(exc)}, sys.stdout)
        sys.exit(1)


if __name__ == "__main__":
    main()
