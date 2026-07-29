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
    if offset < 0:
        offset = 0
    line = text.count("\n", 0, offset) + 1
    last_nl = text.rfind("\n", 0, offset)
    col = offset - last_nl if last_nl >= 0 else offset + 1
    return line, col


def _offset_at_line_col(text: str, line: int, column: int) -> int:
    lines = text.splitlines(keepends=True)
    if line < 1:
        line = 1
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
    match = re.search(r"[\w${}@&][\w\s${}@&.-]*", row[col:])
    if match:
        return match.group(0).strip()
    match = re.search(r"[\w${}@&][\w\s${}@&.-]*$", row[:col])
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
            return value.strip("*").strip().lower()
    return str(header).lower()


def _node_name(item: Any) -> str:
    name = getattr(item, "name", None)
    if name is not None:
        return str(name).strip()
    return ""


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
                value = str(getattr(item, "value", "") or _node_name(item) or path)
                symbols.append(
                    {
                        "name": value.split()[0] if value else Path(path).stem,
                        "kind": "documentation",
                        "line": line,
                        "detail": "Documentation",
                        "documentation": value,
                    },
                )
            elif item_type in {"TestTags", "DefaultTags"}:
                detail = "Force Tags" if item_type == "TestTags" else "Default Tags"
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
                        "detail": "",
                    },
                )
            elif item_type == "Keyword":
                symbols.append(
                    {
                        "name": _node_name(item),
                        "kind": "keyword",
                        "line": line,
                        "detail": "",
                        "documentation": _collect_documentation(item),
                    },
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
                detail = header
                if case_tags:
                    detail = f"{header}|tags:{','.join(case_tags)}"
                symbols.append(
                    {
                        "name": case_name,
                        "kind": kind,
                        "line": line,
                        "detail": detail,
                        "documentation": _collect_documentation(item),
                    },
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

    section = "unknown"
    for idx in range(line - 1, -1, -1):
        candidate = lines[idx].strip()
        if candidate.startswith("*") and candidate.endswith("*"):
            section = candidate.strip("*").strip().lower()
            break

    # Local settings: "    [Doc…" inside Test Cases / Keywords / Tasks.
    local_setting = re.match(r"^(\s*)(\[[^\]]*)\]?", row)
    if local_setting and (row.startswith(" ") or row.startswith("\t")):
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
        return {"prefix": prefix, "context": "setting", "section": section}
    if section == "variables" or prefix.startswith(("${", "@{", "&{")):
        return {"prefix": prefix, "context": "variable", "section": section}
    if section in {"keywords", "test cases", "tasks"}:
        if row.startswith(" ") or row.startswith("\t"):
            # Control markers are typed like keywords inside bodies.
            return {"prefix": prefix, "context": "keyword_call", "section": section}
        return {"prefix": prefix, "context": "keyword", "section": section}
    return {"prefix": prefix, "context": "keyword_call", "section": section}


def _robot_cells(row: str) -> list[str]:
    """Split a Robot Framework row into cells (2+ spaces or tabs)."""
    return [cell for cell in re.split(r"[ \t]{2,}|\t+", row.strip()) if cell]


def signature_help(
    content: str,
    file_path: str,
    line: int,
    column: int,
) -> dict[str, Any] | None:
    _ = file_path
    lines = content.splitlines()
    if line < 1 or line > len(lines):
        return None
    row = lines[line - 1]
    if not (row.startswith(" ") or row.startswith("\t")):
        return None
    cells = _robot_cells(row)
    if not cells:
        return None
    keyword_index = 0
    if re.match(r"^[\$@&%]", cells[0]) and len(cells) > 1:
        keyword_index = 1
    if keyword_index >= len(cells):
        return None
    keyword = cells[keyword_index]
    arguments = cells[keyword_index + 1 :]
    col_in_row = max(0, min(column - 1, len(row)))
    before = _robot_cells(row[:col_in_row])
    arg_index = 0
    if before:
        arg_index = max(0, len(before) - 1 - keyword_index)
    return {
        "keyword": keyword,
        "active_parameter": arg_index,
        "arguments": arguments,
    }


def resolve_library(name: str) -> dict:
    """Resolve a Library import against this environment via Robot libdoc."""
    cleaned = (name or "").strip()
    if not cleaned:
        return {"available": False, "name": "", "keywords": [], "keyword_info": {}}
    try:
        from robot.libdoc import LibraryDocumentation

        doc = LibraryDocumentation(cleaned)
        keywords: list[str] = []
        keyword_info: dict[str, dict] = {}
        for kw in doc.keywords:
            kw_name = str(kw.name)
            keywords.append(kw_name)
            parameters: list[dict[str, str]] = []
            for arg in getattr(kw, "args", []) or []:
                label = str(arg)
                parameters.append({"label": label, "documentation": ""})
            keyword_info[kw_name.casefold()] = {
                "name": kw_name,
                "documentation": str(getattr(kw, "short_doc", None) or ""),
                "parameters": parameters,
            }
        return {
            "available": True,
            "name": str(doc.name or cleaned),
            "keywords": keywords,
            "keyword_info": keyword_info,
        }
    except Exception as exc:  # noqa: BLE001 — import / libdoc failures
        return {
            "available": False,
            "name": cleaned,
            "keywords": [],
            "keyword_info": {},
            "error": str(exc),
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
        elif op == "format":
            result = format_document(content, file_path)
        elif op == "completion_context":
            result = completion_context(content, file_path, line, column)
        elif op == "signature_help":
            result = signature_help(content, file_path, line, column)
        elif op == "resolve_library":
            result = resolve_library(library)
        else:
            raise ValueError(f"Unknown op: {op}")
        json.dump({"ok": True, "result": result}, sys.stdout)
    except Exception as exc:  # noqa: BLE001 — worker boundary
        json.dump({"ok": False, "error": str(exc)}, sys.stdout)
        sys.exit(1)


if __name__ == "__main__":
    main()
