"""Python buffer intelligence — completion context, AST completions, signatures.

Tier 1: symbols + keywords from the open buffer (including ``self.`` members).
Tier 2 consumers use the workspace index separately; tier 3 (Jedi) lives in
``python_jedi.py``.
"""

from __future__ import annotations

import ast
import keyword
import re
from dataclasses import dataclass
from typing import Any

# Stub and script variants are the same language: every gate that enables Python
# intelligence should accept them, so highlighting and features never disagree.
PYTHON_SUFFIXES = (".py", ".pyi", ".pyw")


def is_python_path(file_path: str) -> bool:
    return str(file_path).lower().endswith(PYTHON_SUFFIXES)


_IDENT_TAIL = re.compile(r"[A-Za-z_][\w]*$")
# ``self.`` / ``Class.`` with optional incomplete attribute after the dot.
_ATTR_TAIL = re.compile(r"([A-Za-z_][\w]*)\.([A-Za-z_][\w]*)?$")


def _parse_python(content: str) -> ast.Module | None:
    """Parse buffer AST, tolerating common mid-typing syntax errors."""
    try:
        tree = ast.parse(content)
        return tree if isinstance(tree, ast.Module) else None
    except SyntaxError:
        pass

    lines = content.splitlines()
    patched: list[str] = []
    for row in lines:
        stripped = row.rstrip()
        if re.search(r"\.\s*$", stripped):
            patched.append(re.sub(r"\.\s*$", "._", stripped))
        elif re.search(r"\(\s*$", stripped):
            patched.append(stripped + ")")
        elif re.search(r",\s*$", stripped):
            patched.append(stripped + " _")
        else:
            patched.append(row)
    try:
        tree = ast.parse("\n".join(patched) + ("\n" if content.endswith("\n") else ""))
        return tree if isinstance(tree, ast.Module) else None
    except SyntaxError:
        return None


@dataclass(frozen=True)
class PythonCompletionContext:
    prefix: str
    context: str  # python | python_attr
    attribute_base: str = ""  # e.g. "self" or "Client"


def python_completion_context(
    content: str,
    line: int,
    column: int,
) -> dict[str, Any]:
    """Prefix + context at the caret (1-based line/column)."""
    lines = content.splitlines()
    if line < 1 or line > len(lines):
        return {"prefix": "", "context": "python", "section": "python"}
    row = lines[line - 1]
    col = max(0, min(column - 1, len(row)))
    before = row[:col]

    attr = _ATTR_TAIL.search(before)
    if attr:
        return {
            "prefix": attr.group(2) or "",
            "context": "python_attr",
            "section": "python",
            "attribute_base": attr.group(1),
        }

    ident = _IDENT_TAIL.search(before)
    prefix = ident.group(0) if ident else ""
    return {
        "prefix": prefix,
        "context": "python",
        "section": "python",
        "attribute_base": "",
    }


def python_buffer_completions(
    content: str,
    *,
    line: int,
    column: int,
    prefix: str,
    context: str,
    attribute_base: str = "",
) -> list[dict[str, Any]]:
    """Tier-1 candidates from the current buffer AST."""
    tree = _parse_python(content)

    out: list[dict[str, Any]] = []
    seen: set[str] = set()

    def _add(
        label: str,
        *,
        kind: str,
        detail: str,
        documentation: str = "",
        insert_text: str | None = None,
    ) -> None:
        if not label or label in seen:
            return
        if prefix and not _prefix_match(label, prefix):
            return
        seen.add(label)
        out.append(
            {
                "label": label,
                "kind": kind,
                "detail": detail,
                "documentation": documentation,
                "insert_text": insert_text or label,
            },
        )

    if context == "python_attr" and attribute_base:
        if tree is not None:
            for item in _attribute_completions(tree, line, attribute_base):
                _add(
                    item["label"],
                    kind=item["kind"],
                    detail=item["detail"],
                    documentation=item.get("documentation", ""),
                )
        return out

    # Language keywords (when typing an identifier).
    for word in keyword.kwlist:
        _add(word, kind="keyword", detail="Python keyword")

    if tree is None:
        return out

    enclosing = _enclosing_class(tree, line)
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            _add(node.name, kind="class", detail="class")
            for item in node.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    if item.name.startswith("__") and item.name.endswith("__"):
                        continue
                    if item.name.startswith("_"):
                        continue
                    _add(
                        item.name,
                        kind="method",
                        detail=f"{node.name}.{item.name}",
                        documentation=ast.get_docstring(item) or "",
                    )
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if not node.name.startswith("_"):
                _add(
                    node.name,
                    kind="function",
                    detail="function",
                    documentation=ast.get_docstring(node) or "",
                )
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            for name in _assignment_names(node):
                if name.startswith("_"):
                    continue
                _add(name, kind="variable", detail="variable")

    if enclosing is not None:
        _add("self", kind="variable", detail=f"{enclosing.name} instance")
        for item in enclosing.body:
            if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                if item.name.startswith("_") and item.name != "__init__":
                    continue
                _add(
                    item.name,
                    kind="method",
                    detail=f"{enclosing.name}.{item.name}",
                    documentation=ast.get_docstring(item) or "",
                )

    # Imports in this buffer.
    for node in tree.body:
        if isinstance(node, ast.Import):
            for alias in node.names:
                _add(alias.asname or alias.name.split(".")[0], kind="module", detail="import")
        elif isinstance(node, ast.ImportFrom):
            for alias in node.names:
                if alias.name == "*":
                    continue
                _add(alias.asname or alias.name, kind="module", detail="from-import")

    return out


def python_signature_help(
    content: str,
    line: int,
    column: int,
) -> dict[str, Any] | None:
    """Signature card for a call under the caret, or the ``def`` being written."""
    tree = _parse_python(content)
    if tree is None:
        return None

    call = _innermost_call(tree, line, column)
    if call is not None:
        name = _call_name(call)
        if name:
            target = _find_function(tree, name)
            if target is not None:
                return _signature_payload(target, active=_active_arg_index(content, line, column))

    # Only the ``def`` header itself, never the whole body: a card pinned to the
    # enclosing function would cover every line the caret visits.
    enclosing = _enclosing_function(tree, line)
    if enclosing is not None and _in_function_header(enclosing, line):
        return _signature_payload(enclosing, active=0)
    return None


def _in_function_header(
    node: ast.FunctionDef | ast.AsyncFunctionDef,
    line: int,
) -> bool:
    start = getattr(node, "lineno", 1) or 1
    body_start = min(
        (getattr(stmt, "lineno", start) or start for stmt in node.body),
        default=start + 1,
    )
    return start <= line < body_start


def _prefix_match(label: str, prefix: str) -> bool:
    if not prefix:
        return True
    return label.casefold().startswith(prefix.casefold())


def _assignment_names(stmt: ast.stmt) -> list[str]:
    names: list[str] = []
    if isinstance(stmt, ast.Assign):
        for target in stmt.targets:
            names.extend(_names_from_target(target))
    elif isinstance(stmt, ast.AnnAssign) and stmt.target is not None:
        names.extend(_names_from_target(stmt.target))
    return names


def _names_from_target(target: ast.expr) -> list[str]:
    if isinstance(target, ast.Name):
        return [target.id]
    if isinstance(target, (ast.Tuple, ast.List)):
        out: list[str] = []
        for elt in target.elts:
            out.extend(_names_from_target(elt))
        return out
    return []


def _enclosing_class(tree: ast.AST, line: int) -> ast.ClassDef | None:
    best: ast.ClassDef | None = None
    for node in ast.walk(tree):
        if not isinstance(node, ast.ClassDef):
            continue
        start = getattr(node, "lineno", 1) or 1
        end = getattr(node, "end_lineno", start) or start
        if start <= line <= end:
            if best is None or start >= (getattr(best, "lineno", 0) or 0):
                best = node
    return best


def _enclosing_function(
    tree: ast.AST,
    line: int,
) -> ast.FunctionDef | ast.AsyncFunctionDef | None:
    best: ast.FunctionDef | ast.AsyncFunctionDef | None = None
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        start = getattr(node, "lineno", 1) or 1
        end = getattr(node, "end_lineno", start) or start
        if start <= line <= end:
            if best is None or start >= (getattr(best, "lineno", 0) or 0):
                best = node
    return best


def _attribute_completions(
    tree: ast.Module,
    line: int,
    base: str,
) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    if base == "self":
        cls = _enclosing_class(tree, line)
        if cls is None:
            return out
        for item in cls.body:
            if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                if item.name.startswith("_") and not (
                    item.name.startswith("__") and item.name.endswith("__")
                ):
                    if item.name != "__init__":
                        continue
                out.append(
                    {
                        "label": item.name,
                        "kind": "method",
                        "detail": f"{cls.name}.{item.name}",
                        "documentation": ast.get_docstring(item) or "",
                    },
                )
            elif isinstance(item, ast.AnnAssign) and isinstance(item.target, ast.Name):
                out.append(
                    {
                        "label": item.target.id,
                        "kind": "variable",
                        "detail": f"{cls.name} attribute",
                        "documentation": "",
                    },
                )
        return out

    # ClassName. → class methods / nested names
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == base:
            for item in node.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    if item.name.startswith("_"):
                        continue
                    out.append(
                        {
                            "label": item.name,
                            "kind": "method",
                            "detail": f"{node.name}.{item.name}",
                            "documentation": ast.get_docstring(item) or "",
                        },
                    )
    return out


def _innermost_call(tree: ast.AST, line: int, column: int) -> ast.Call | None:
    best: ast.Call | None = None
    best_span = 10**9
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        start = getattr(node, "lineno", None)
        end = getattr(node, "end_lineno", None)
        if start is None:
            continue
        end = end or start
        if not (start <= line <= end):
            continue
        span = (end - start) * 1000 + (
            (getattr(node, "end_col_offset", 0) or 0)
            - (getattr(node, "col_offset", 0) or 0)
        )
        if span <= best_span:
            best = node
            best_span = span
    return best


def _call_name(call: ast.Call) -> str:
    func = call.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return ""


def _find_function(
    tree: ast.AST,
    name: str,
) -> ast.FunctionDef | ast.AsyncFunctionDef | None:
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name:
            return node
    return None


def _active_arg_index(content: str, line: int, column: int) -> int:
    lines = content.splitlines()
    if line < 1 or line > len(lines):
        return 0
    row = lines[line - 1][: max(0, column - 1)]
    # Count commas after the last open '(' on this line (heuristic).
    open_at = row.rfind("(")
    if open_at < 0:
        return 0
    fragment = row[open_at + 1 :]
    return fragment.count(",")


def _signature_payload(
    node: ast.FunctionDef | ast.AsyncFunctionDef,
    *,
    active: int,
) -> dict[str, Any]:
    params: list[dict[str, Any]] = []
    args = node.args
    positional = list(args.args)
    defaults = list(args.defaults)
    default_offset = len(positional) - len(defaults)
    for index, arg in enumerate(positional):
        if arg.arg in {"self", "cls"}:
            continue
        has_default = index >= default_offset
        default_val = ""
        if has_default:
            default_val = _ast_default_str(defaults[index - default_offset])
        params.append(
            {
                "name": arg.arg,
                "label": arg.arg + (f"={default_val}" if has_default else ""),
                "default": default_val,
                "required": not has_default,
                "kind": "positional_or_keyword",
                "type_name": "",
                "documentation": "",
            },
        )
    for arg in args.kwonlyargs:
        params.append(
            {
                "name": arg.arg,
                "label": arg.arg,
                "default": "",
                "required": True,
                "kind": "keyword_only",
                "type_name": "",
                "documentation": "",
            },
        )
    label_parts = [p["label"] for p in params]
    return {
        "keyword": node.name,
        "label": f"{node.name}({', '.join(label_parts)})",
        "detail": f"{node.name}({', '.join(label_parts)})",
        "documentation": ast.get_docstring(node) or "",
        "parameters": params,
        "active_parameter": max(0, min(active, max(0, len(params) - 1))),
        "source_type": "python",
        "library_name": "",
    }


def _ast_default_str(node: ast.AST) -> str:
    try:
        return ast.unparse(node)
    except Exception:  # noqa: BLE001
        return "…"
