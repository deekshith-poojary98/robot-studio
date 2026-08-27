"""Document outline for Python buffers via the stdlib AST.

Produces the same DocumentSymbolTree shape as Robot ``document_symbol_tree``
so Outline / breadcrumbs / folding can consume either language.
"""

from __future__ import annotations

import ast
from pathlib import Path
from typing import Any


def python_document_symbol_tree(content: str, file_path: str) -> dict[str, Any]:
    """Build a nested symbol tree for a ``.py`` buffer."""
    path = file_path or "module.py"
    stem = Path(path).stem or Path(path).name
    try:
        module = ast.parse(content)
    except SyntaxError:
        module = None

    children: list[dict[str, Any]] = []
    if module is not None:
        children = _body_symbols(list(module.body), in_class=False)

    end_line = 1
    if children:
        end_line = max(int(c.get("end_line") or c.get("line") or 1) for c in children)
    elif module is not None and getattr(module, "end_lineno", None):
        end_line = int(module.end_lineno or 1)

    return {
        "file_path": path,
        "root": _node(
            name=stem,
            kind="file",
            line=1,
            end_line=end_line,
            detail="Python",
            children=children,
        ),
    }


def _body_symbols(
    body: list[ast.stmt],
    *,
    in_class: bool,
    include_assigns: bool = True,
) -> list[dict[str, Any]]:
    """Symbols for a module, class, or function body.

    Locals inside a function stay out of the outline (too noisy). Class bodies
    list attributes first — annotated/assigned fields, then ``self.`` / ``cls.``
    writes from methods — then methods, matching how VS Code groups a class.
    """
    fields: list[dict[str, Any]] = []
    members: list[dict[str, Any]] = []
    instance_fields: list[dict[str, Any]] = []
    module_nodes: list[dict[str, Any]] = []
    for stmt in body:
        if isinstance(stmt, ast.ClassDef):
            node = _node(
                name=stmt.name,
                kind="class",
                line=_lineno(stmt),
                end_line=_end_lineno(stmt),
                column=_col(stmt),
                detail="class",
                children=_body_symbols(list(stmt.body), in_class=True),
            )
            (members if in_class else module_nodes).append(node)
        elif isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
            async_fn = isinstance(stmt, ast.AsyncFunctionDef)
            kind = "method" if in_class else "function"
            detail = "async method" if async_fn and in_class else (
                "async" if async_fn else ("method" if in_class else "function")
            )
            if in_class:
                instance_fields.extend(_instance_attributes(list(stmt.body)))
            node = _node(
                name=stmt.name,
                kind=kind,
                line=_lineno(stmt),
                end_line=_end_lineno(stmt),
                column=_col(stmt),
                detail=detail,
                children=_body_symbols(
                    list(stmt.body),
                    in_class=False,
                    include_assigns=False,
                ),
            )
            (members if in_class else module_nodes).append(node)
        elif include_assigns and isinstance(
            stmt, (ast.Assign, ast.AnnAssign, ast.AugAssign)
        ):
            for name in _assignment_names(stmt):
                node = _variable_node(name, stmt, detail="variable")
                if node is None:
                    continue
                (fields if in_class else module_nodes).append(node)
    if not in_class:
        return module_nodes

    seen = {node["name"] for node in fields}
    extras: list[dict[str, Any]] = []
    for node in instance_fields:
        name = str(node.get("name") or "")
        if name in seen:
            continue
        seen.add(name)
        extras.append(node)
    extras.sort(key=lambda item: (int(item.get("line") or 1), str(item.get("name") or "")))
    return fields + extras + members


def _variable_node(name: str, stmt: ast.stmt, *, detail: str) -> dict[str, Any] | None:
    if name.startswith("_") and name != "_":
        return None
    return _node(
        name=name,
        kind="variable",
        line=_lineno(stmt),
        end_line=_end_lineno(stmt),
        column=_col(stmt),
        detail=detail,
    )


def _instance_attributes(body: list[ast.stmt]) -> list[dict[str, Any]]:
    """``self.x`` / ``cls.x`` writes in a method — listed on the class, not as locals."""
    nodes: list[dict[str, Any]] = []
    seen: set[str] = set()
    for stmt in body:
        if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        if not isinstance(stmt, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
            continue
        for name in _self_attribute_names(stmt):
            if name in seen:
                continue
            node = _variable_node(name, stmt, detail="attribute")
            if node is None:
                continue
            seen.add(name)
            nodes.append(node)
    return nodes


def _self_attribute_names(stmt: ast.stmt) -> list[str]:
    targets: list[ast.expr] = []
    if isinstance(stmt, ast.Assign):
        targets.extend(stmt.targets)
    elif isinstance(stmt, ast.AnnAssign) and stmt.target is not None:
        targets.append(stmt.target)
    elif isinstance(stmt, ast.AugAssign):
        targets.append(stmt.target)
    names: list[str] = []
    for target in targets:
        names.extend(_names_from_self_attr(target))
    return names


def _names_from_self_attr(target: ast.expr) -> list[str]:
    if isinstance(target, ast.Attribute) and isinstance(target.value, ast.Name):
        if target.value.id in {"self", "cls"} and target.attr:
            return [target.attr]
        return []
    if isinstance(target, (ast.Tuple, ast.List)):
        out: list[str] = []
        for elt in target.elts:
            out.extend(_names_from_self_attr(elt))
        return out
    return []


def _assignment_names(stmt: ast.stmt) -> list[str]:
    names: list[str] = []
    if isinstance(stmt, ast.Assign):
        for target in stmt.targets:
            names.extend(_names_from_target(target))
    elif isinstance(stmt, ast.AnnAssign) and stmt.target is not None:
        names.extend(_names_from_target(stmt.target))
    elif isinstance(stmt, ast.AugAssign):
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


def _lineno(node: ast.AST) -> int:
    return max(1, int(getattr(node, "lineno", 1) or 1))


def _end_lineno(node: ast.AST) -> int:
    end = getattr(node, "end_lineno", None)
    if end is not None:
        return max(1, int(end))
    return _lineno(node)


def _col(node: ast.AST) -> int:
    return max(1, int(getattr(node, "col_offset", 0) or 0) + 1)


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
    return {
        "name": name,
        "kind": kind,
        "line": line,
        "end_line": end_line if end_line is not None else line,
        "column": column,
        "detail": detail,
        "documentation": documentation,
        "children": children or [],
    }
