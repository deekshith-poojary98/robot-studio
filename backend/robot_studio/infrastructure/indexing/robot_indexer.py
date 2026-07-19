"""Lightweight Robot Framework file symbol extraction."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from uuid import UUID

from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import IndexedSymbol

_SECTION_RE = re.compile(r"^\*+\s*(settings|variables|keywords|test cases|tasks)\s*\**", re.I)
_SETTING_RE = re.compile(
    r"^(Library|Resource|Variables|Documentation|Suite Setup|Suite Teardown|"
    r"Test Setup|Test Teardown|Test Timeout|Force Tags|Default Tags|Metadata)\s+",
    re.I,
)
_VAR_RE = re.compile(r"^(\$\{[^}]+\}|@\{[^}]+\}|&\{[^}]+\})\s+")
_DOC_CONTINUE = re.compile(r"^\.\.\.\s+(.*)$")


def _sid(kind: str, file_path: Path, name: str, line: int) -> str:
    raw = f"{kind}:{file_path}:{name}:{line}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:24]


class RobotIndexer:
    """Extracts symbols from .robot / .resource files without a full parser."""

    INDEXABLE_SUFFIXES = {".robot", ".resource"}

    def index_file(
        self,
        path: Path,
        *,
        workspace_id: UUID | None,
        project_id: UUID | None,
    ) -> tuple[list[IndexedSymbol], list[dict]]:
        text = path.read_text(encoding="utf-8", errors="replace")
        mtime = path.stat().st_mtime
        lines = text.splitlines()
        symbols: list[IndexedSymbol] = []
        references: list[dict] = []

        symbols.append(
            IndexedSymbol(
                id=_sid(SymbolKind.FILE.value, path, path.name, 1),
                name=path.name,
                kind=SymbolKind.FILE.value,
                file_path=path,
                line=1,
                project_id=project_id,
                workspace_id=workspace_id,
                detail=str(path.suffix.lstrip(".")),
                last_modified=mtime,
            ),
        )

        if path.suffix.lower() == ".robot":
            symbols.append(
                IndexedSymbol(
                    id=_sid(SymbolKind.TEST_SUITE.value, path, path.stem, 1),
                    name=path.stem,
                    kind=SymbolKind.TEST_SUITE.value,
                    file_path=path,
                    line=1,
                    project_id=project_id,
                    workspace_id=workspace_id,
                    last_modified=mtime,
                ),
            )
        elif path.suffix.lower() == ".resource":
            symbols.append(
                IndexedSymbol(
                    id=_sid(SymbolKind.RESOURCE.value, path, path.stem, 1),
                    name=path.stem,
                    kind=SymbolKind.RESOURCE.value,
                    file_path=path,
                    line=1,
                    project_id=project_id,
                    workspace_id=workspace_id,
                    detail="resource",
                    last_modified=mtime,
                ),
            )

        section: str | None = None
        current_name: str | None = None
        current_kind: SymbolKind | None = None
        current_line = 1
        current_doc: list[str] = []
        in_test_body = False

        def flush_current() -> None:
            nonlocal current_name, current_kind, current_line, current_doc
            if not current_name or current_kind is None:
                return
            symbols.append(
                IndexedSymbol(
                    id=_sid(current_kind.value, path, current_name, current_line),
                    name=current_name,
                    kind=current_kind.value,
                    file_path=path,
                    line=current_line,
                    project_id=project_id,
                    workspace_id=workspace_id,
                    documentation="\n".join(current_doc).strip(),
                    last_modified=mtime,
                ),
            )
            current_name = None
            current_kind = None
            current_doc = []

        for idx, raw in enumerate(lines, start=1):
            line = raw.rstrip()
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            section_match = _SECTION_RE.match(stripped)
            if section_match:
                flush_current()
                section = section_match.group(1).lower()
                in_test_body = False
                continue

            if section == "settings":
                setting_match = _SETTING_RE.match(stripped)
                if setting_match:
                    flush_current()
                    setting = setting_match.group(1)
                    rest = stripped[setting_match.end() :].strip()
                    name = rest.split()[0] if rest else setting
                    kind = SymbolKind.SETTING
                    if setting.lower() == "library":
                        kind = SymbolKind.LIBRARY
                    elif setting.lower() == "resource":
                        kind = SymbolKind.RESOURCE
                    elif setting.lower() == "documentation":
                        kind = SymbolKind.DOCUMENTATION
                        name = path.stem
                    symbols.append(
                        IndexedSymbol(
                            id=_sid(kind.value, path, name, idx),
                            name=name,
                            kind=kind.value,
                            file_path=path,
                            line=idx,
                            project_id=project_id,
                            workspace_id=workspace_id,
                            detail=setting,
                            documentation=rest if kind == SymbolKind.DOCUMENTATION else "",
                            last_modified=mtime,
                        ),
                    )
                    if setting.lower() in {"force tags", "default tags"}:
                        for tag in rest.split():
                            symbols.append(
                                IndexedSymbol(
                                    id=_sid(SymbolKind.TAG.value, path, tag, idx),
                                    name=tag,
                                    kind=SymbolKind.TAG.value,
                                    file_path=path,
                                    line=idx,
                                    project_id=project_id,
                                    workspace_id=workspace_id,
                                    last_modified=mtime,
                                ),
                            )
                continue

            if section == "variables":
                var_match = _VAR_RE.match(stripped)
                if var_match:
                    flush_current()
                    name = var_match.group(1)
                    symbols.append(
                        IndexedSymbol(
                            id=_sid(SymbolKind.VARIABLE.value, path, name, idx),
                            name=name,
                            kind=SymbolKind.VARIABLE.value,
                            file_path=path,
                            line=idx,
                            project_id=project_id,
                            workspace_id=workspace_id,
                            detail=stripped[var_match.end() :].strip()[:120],
                            last_modified=mtime,
                        ),
                    )
                continue

            if section in {"keywords", "test cases", "tasks"}:
                # Nested table cells start with whitespace → body / call.
                if line[:1].isspace():
                    body = stripped
                    if body.lower().startswith("[documentation]"):
                        doc = body.split("]", 1)[-1].strip()
                        if doc:
                            current_doc.append(doc)
                    elif body.lower().startswith("[tags]"):
                        tags = body.split("]", 1)[-1].strip().split()
                        for tag in tags:
                            symbols.append(
                                IndexedSymbol(
                                    id=_sid(SymbolKind.TAG.value, path, tag, idx),
                                    name=tag,
                                    kind=SymbolKind.TAG.value,
                                    file_path=path,
                                    line=idx,
                                    project_id=project_id,
                                    workspace_id=workspace_id,
                                    last_modified=mtime,
                                ),
                            )
                    elif not body.startswith("["):
                        # Likely a keyword call — record reference for first token.
                        call = body.split("  ")[0].split("\t")[0].strip()
                        if call and not call.startswith(("$", "@", "&", "#")):
                            references.append(
                                {
                                    "symbol_id": "",
                                    "name": call,
                                    "file_path": str(path),
                                    "line": idx,
                                    "project_id": str(project_id) if project_id else None,
                                    "context": body[:160],
                                },
                            )
                    in_test_body = True
                    continue

                # New keyword / test case definition.
                flush_current()
                name = stripped.split("  ")[0].split("\t")[0].strip()
                if not name:
                    continue
                current_name = name
                current_line = idx
                current_doc = []
                current_kind = (
                    SymbolKind.KEYWORD
                    if section == "keywords"
                    else SymbolKind.TEST_CASE
                )
                in_test_body = False
                continue

            _ = in_test_body

        flush_current()
        return symbols, references
