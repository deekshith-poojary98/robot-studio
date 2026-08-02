"""Extract semantic facts from Robot files using robot.api.parsing only."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from uuid import UUID

from robot.api import get_model
from robot.api.parsing import ModelVisitor, Token

from robot_studio.domain.models.analysis import (
    BindingConfidence,
    EdgeKind,
    EntityKind,
    SemanticEdge,
    SemanticEntity,
)
from robot_studio.infrastructure.analysis.normalize import (
    normalize_keyword_name,
    normalize_variable_name,
)


def stable_entity_id(kind: str, file_path: Path, name_normalized: str) -> str:
    raw = f"{kind}|{file_path.resolve().as_posix()}|{name_normalized}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:24]


def _line_col(node: Any) -> tuple[int, int]:
    line = int(getattr(node, "lineno", None) or getattr(node, "line", None) or 1)
    col = int(getattr(node, "col_offset", None) or getattr(node, "col", None) or 1)
    if col < 1:
        col = 1
    return line, col


def _node_name(node: Any) -> str:
    name = getattr(node, "name", None)
    if name is not None:
        return str(name).strip()
    return ""


def _documentation(item: Any) -> str:
    docs: list[str] = []
    for entry in getattr(item, "body", None) or []:
        if type(entry).__name__ != "Documentation":
            continue
        value = getattr(entry, "value", None)
        if value:
            docs.append(str(value))
            continue
        values = getattr(entry, "values", None) or []
        if values:
            docs.append(" ".join(str(v) for v in values))
    return "\n".join(docs).strip()


def _variables_in_string(text: str) -> list[str]:
    """Use Robot Framework's VariableMatches — not ad-hoc regex parsing."""
    if not text:
        return []
    if "$" not in text and "@" not in text and "&" not in text and "%" not in text:
        return []
    try:
        from robot.variables.search import VariableMatches
    except ImportError:  # pragma: no cover
        return []
    found: list[str] = []
    for match in VariableMatches(text):
        name = getattr(match, "name", None)
        if name:
            found.append(str(name))
    return found


@dataclass
class FileSemanticFacts:
    entities: list[SemanticEntity] = field(default_factory=list)
    edges: list[SemanticEdge] = field(default_factory=list)


class _SemanticVisitor(ModelVisitor):
    def __init__(
        self,
        path: Path,
        *,
        workspace_id: UUID | None,
        project_id: UUID | None,
    ) -> None:
        self.path = path.resolve()
        self.workspace_id = workspace_id
        self.project_id = project_id
        self.entities: list[SemanticEntity] = []
        self.edges: list[SemanticEdge] = []
        self._file_id = stable_entity_id(
            EntityKind.FILE.value,
            self.path,
            normalize_keyword_name(self.path.name),
        )
        self._suite_id: str | None = None
        self._current_owner_id: str | None = None
        self._suite_template: str | None = None

    def visit_File(self, node):  # noqa: N802
        self.entities.append(
            SemanticEntity(
                id=self._file_id,
                kind=EntityKind.FILE,
                name=self.path.name,
                name_normalized=normalize_keyword_name(self.path.name),
                file_path=self.path,
                line=1,
                column=1,
                detail=self.path.suffix.lstrip("."),
                project_id=self.project_id,
                workspace_id=self.workspace_id,
                qualified_name=self.path.as_posix(),
            ),
        )
        has_tests = any(type(s).__name__ == "TestCaseSection" for s in node.sections)
        if self.path.suffix.lower() == ".resource" or (
            self.path.suffix.lower() == ".robot" and not has_tests
        ):
            kind = EntityKind.RESOURCE
            name = self.path.stem
        else:
            kind = EntityKind.SUITE
            name = self.path.stem
        self._suite_id = stable_entity_id(
            kind.value,
            self.path,
            normalize_keyword_name(name),
        )
        self.entities.append(
            SemanticEntity(
                id=self._suite_id,
                kind=kind,
                name=name,
                name_normalized=normalize_keyword_name(name),
                file_path=self.path,
                line=1,
                column=1,
                project_id=self.project_id,
                workspace_id=self.workspace_id,
                qualified_name=f"{self.path.as_posix()}::{name}",
            ),
        )
        self.edges.append(
            SemanticEdge(
                edge_kind=EdgeKind.CONTAINS,
                source_id=self._file_id,
                target_id=self._suite_id,
                source_file=self.path,
                source_line=1,
                confidence=BindingConfidence.EXACT,
                project_id=self.project_id,
                context="file-contains",
            ),
        )
        return self.generic_visit(node)

    def visit_LibraryImport(self, node):  # noqa: N802
        name = _node_name(node) or str(getattr(node, "name", "") or "")
        if not name:
            return
        line, col = _line_col(node)
        lib_id = stable_entity_id(
            EntityKind.LIBRARY.value,
            self.path,
            normalize_keyword_name(name),
        )
        # Library nodes are scoped to importing file for graph locality;
        # binder may later merge by normalized name across project.
        self.entities.append(
            SemanticEntity(
                id=lib_id,
                kind=EntityKind.LIBRARY,
                name=name,
                name_normalized=normalize_keyword_name(name),
                file_path=self.path,
                line=line,
                column=col,
                detail="Library",
                project_id=self.project_id,
                workspace_id=self.workspace_id,
                qualified_name=name,
            ),
        )
        source = self._suite_id or self._file_id
        alias = getattr(node, "alias", None)
        self.edges.append(
            SemanticEdge(
                edge_kind=EdgeKind.IMPORTS_LIBRARY,
                source_id=source,
                target_id=lib_id,
                source_file=self.path,
                source_line=line,
                source_column=col,
                target_name=name,
                target_name_normalized=normalize_keyword_name(name),
                confidence=BindingConfidence.EXACT,
                project_id=self.project_id,
                context=f"alias={alias}" if alias else "",
            ),
        )

    def visit_ResourceImport(self, node):  # noqa: N802
        name = _node_name(node) or str(getattr(node, "name", "") or "")
        if not name:
            return
        line, col = _line_col(node)
        source = self._suite_id or self._file_id
        self.edges.append(
            SemanticEdge(
                edge_kind=EdgeKind.IMPORTS_RESOURCE,
                source_id=source,
                target_id=None,
                source_file=self.path,
                source_line=line,
                source_column=col,
                target_name=name,
                target_name_normalized=normalize_keyword_name(Path(name).name),
                confidence=BindingConfidence.LOW,
                project_id=self.project_id,
                context="Resource",
            ),
        )

    def visit_VariablesImport(self, node):  # noqa: N802
        name = _node_name(node) or str(getattr(node, "name", "") or "")
        if not name:
            return
        line, col = _line_col(node)
        source = self._suite_id or self._file_id
        self.edges.append(
            SemanticEdge(
                edge_kind=EdgeKind.IMPORTS_VARIABLES,
                source_id=source,
                target_id=None,
                source_file=self.path,
                source_line=line,
                source_column=col,
                target_name=name,
                target_name_normalized=normalize_keyword_name(Path(name).name),
                confidence=BindingConfidence.LOW,
                project_id=self.project_id,
                context="Variables",
            ),
        )

    def visit_Variable(self, node):  # noqa: N802
        name = _node_name(node)
        if not name:
            return
        line, col = _line_col(node)
        norm = normalize_variable_name(name)
        var_id = stable_entity_id(EntityKind.VARIABLE.value, self.path, norm)
        self.entities.append(
            SemanticEntity(
                id=var_id,
                kind=EntityKind.VARIABLE,
                name=name,
                name_normalized=norm,
                file_path=self.path,
                line=line,
                column=col,
                project_id=self.project_id,
                workspace_id=self.workspace_id,
                qualified_name=name,
            ),
        )
        owner = self._suite_id or self._file_id
        self.edges.append(
            SemanticEdge(
                edge_kind=EdgeKind.CONTAINS,
                source_id=owner,
                target_id=var_id,
                source_file=self.path,
                source_line=line,
                source_column=col,
                confidence=BindingConfidence.EXACT,
                project_id=self.project_id,
            ),
        )
        for value in getattr(node, "value", ()) or ():
            self._emit_variable_refs(str(value), owner, line, col)

    def visit_Keyword(self, node):  # noqa: N802
        name = _node_name(node)
        if not name:
            return
        line, col = _line_col(node)
        norm = normalize_keyword_name(name)
        kw_id = stable_entity_id(EntityKind.KEYWORD.value, self.path, norm)
        self.entities.append(
            SemanticEntity(
                id=kw_id,
                kind=EntityKind.KEYWORD,
                name=name,
                name_normalized=norm,
                file_path=self.path,
                line=line,
                column=col,
                documentation=_documentation(node),
                project_id=self.project_id,
                workspace_id=self.workspace_id,
                qualified_name=f"{self.path.as_posix()}::{name}",
            ),
        )
        owner = self._suite_id or self._file_id
        self.edges.append(
            SemanticEdge(
                edge_kind=EdgeKind.CONTAINS,
                source_id=owner,
                target_id=kw_id,
                source_file=self.path,
                source_line=line,
                source_column=col,
                confidence=BindingConfidence.EXACT,
                project_id=self.project_id,
            ),
        )
        previous = self._current_owner_id
        self._current_owner_id = kw_id
        self.generic_visit(node)
        self._current_owner_id = previous

    def visit_TestCase(self, node):  # noqa: N802
        name = _node_name(node)
        if not name:
            return
        line, col = _line_col(node)
        norm = normalize_keyword_name(name)
        test_id = stable_entity_id(EntityKind.TEST_CASE.value, self.path, norm)
        tags: list[str] = []
        for entry in getattr(node, "body", []) or []:
            if type(entry).__name__ == "Tags":
                tags.extend(str(t) for t in (getattr(entry, "values", ()) or ()))
        self.entities.append(
            SemanticEntity(
                id=test_id,
                kind=EntityKind.TEST_CASE,
                name=name,
                name_normalized=norm,
                file_path=self.path,
                line=line,
                column=col,
                documentation=_documentation(node),
                detail=("tags:" + ",".join(tags)) if tags else "",
                project_id=self.project_id,
                workspace_id=self.workspace_id,
                qualified_name=f"{self.path.as_posix()}::{name}",
            ),
        )
        owner = self._suite_id or self._file_id
        self.edges.append(
            SemanticEdge(
                edge_kind=EdgeKind.CONTAINS,
                source_id=owner,
                target_id=test_id,
                source_file=self.path,
                source_line=line,
                source_column=col,
                confidence=BindingConfidence.EXACT,
                project_id=self.project_id,
            ),
        )
        for tag in tags:
            tag_norm = normalize_keyword_name(tag)
            tag_id = stable_entity_id(EntityKind.TAG.value, self.path, f"{norm}:{tag_norm}")
            self.entities.append(
                SemanticEntity(
                    id=tag_id,
                    kind=EntityKind.TAG,
                    name=tag,
                    name_normalized=tag_norm,
                    file_path=self.path,
                    line=line,
                    column=col,
                    detail=f"test:{name}",
                    project_id=self.project_id,
                    workspace_id=self.workspace_id,
                ),
            )
            self.edges.append(
                SemanticEdge(
                    edge_kind=EdgeKind.TAGGED,
                    source_id=test_id,
                    target_id=tag_id,
                    source_file=self.path,
                    source_line=line,
                    source_column=col,
                    target_name=tag,
                    target_name_normalized=tag_norm,
                    confidence=BindingConfidence.EXACT,
                    project_id=self.project_id,
                ),
            )
        previous = self._current_owner_id
        self._current_owner_id = test_id
        # Template rows on this test
        test_template = None
        for entry in getattr(node, "body", []) or []:
            if type(entry).__name__ == "Template":
                test_template = str(entry.get_token(Token.NAME) or "") or _node_name(entry)
            elif type(entry).__name__ == "TemplateArguments" and (
                test_template or self._suite_template
            ):
                kw_name = test_template or self._suite_template or ""
                args = [str(t) for t in entry.get_tokens(Token.ARGUMENT)]
                self._emit_call(kw_name, args, entry, count_as_call=True)
        self.generic_visit(node)
        self._current_owner_id = previous

    def visit_TestTemplate(self, node):  # noqa: N802
        value = getattr(node, "value", None)
        if value:
            self._suite_template = str(value)
            self._emit_call(str(value), (), node, count_as_call=True)

    def visit_KeywordCall(self, node):  # noqa: N802
        keyword = str(getattr(node, "keyword", "") or "").strip()
        if not keyword:
            return
        args = tuple(str(a) for a in (getattr(node, "args", ()) or ()))
        self._emit_call(keyword, args, node, count_as_call=True)

    def visit_Setup(self, node):  # noqa: N802
        self._emit_setting_call(node)

    def visit_Teardown(self, node):  # noqa: N802
        self._emit_setting_call(node)

    def visit_TestSetup(self, node):  # noqa: N802
        self._emit_named_call(node)

    def visit_TestTeardown(self, node):  # noqa: N802
        self._emit_named_call(node)

    def visit_SuiteSetup(self, node):  # noqa: N802
        self._emit_named_call(node)

    def visit_SuiteTeardown(self, node):  # noqa: N802
        self._emit_named_call(node)

    def _emit_setting_call(self, node: Any) -> None:
        token = node.get_token(Token.NAME) if hasattr(node, "get_token") else None
        name = str(token) if token else _node_name(node)
        if name:
            self._emit_call(name, (), node, count_as_call=True)

    def _emit_named_call(self, node: Any) -> None:
        name = _node_name(node)
        if not name:
            return
        args = tuple(str(a) for a in (getattr(node, "args", ()) or ()))
        self._emit_call(name, args, node, count_as_call=True)

    def _emit_call(
        self,
        keyword: str,
        args: tuple[str, ...] | list[str],
        node: Any,
        *,
        count_as_call: bool,
    ) -> None:
        if not keyword:
            return
        line, col = _line_col(node)
        source_id = self._current_owner_id or self._suite_id or self._file_id
        if count_as_call:
            self.edges.append(
                SemanticEdge(
                    edge_kind=EdgeKind.CALLS,
                    source_id=source_id,
                    target_id=None,
                    source_file=self.path,
                    source_line=line,
                    source_column=col,
                    target_name=keyword,
                    target_name_normalized=normalize_keyword_name(keyword),
                    confidence=BindingConfidence.LOW,
                    project_id=self.project_id,
                    context="call",
                ),
            )
        for arg in args:
            self._emit_variable_refs(arg, source_id, line, col)

    def _emit_variable_refs(
        self,
        text: str,
        source_id: str,
        line: int,
        col: int,
    ) -> None:
        for var in _variables_in_string(text):
            norm = normalize_variable_name(var)
            if not norm:
                continue
            self.edges.append(
                SemanticEdge(
                    edge_kind=EdgeKind.REFERENCES_VARIABLE,
                    source_id=source_id,
                    target_id=None,
                    source_file=self.path,
                    source_line=line,
                    source_column=col,
                    target_name=var if var.startswith(("$", "@", "&", "%")) else f"${{{var}}}",
                    target_name_normalized=norm,
                    confidence=BindingConfidence.LOW,
                    project_id=self.project_id,
                    context="variable",
                ),
            )


def extract_file_semantics(
    path: Path,
    *,
    workspace_id: UUID | None = None,
    project_id: UUID | None = None,
    content: str | None = None,
) -> FileSemanticFacts:
    """Parse a .robot / .resource file into entities + unbound edges."""
    source = content if content is not None else path.read_text(encoding="utf-8", errors="replace")
    model = get_model(source)
    # Attach path so visit_File can resolve source
    model.source = path
    visitor = _SemanticVisitor(path, workspace_id=workspace_id, project_id=project_id)
    visitor.visit(model)
    return FileSemanticFacts(entities=visitor.entities, edges=visitor.edges)
