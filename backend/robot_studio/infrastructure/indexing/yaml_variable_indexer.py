"""Index Robot Framework YAML / dict variable files."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from uuid import UUID

from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import IndexedSymbol

# Simple KEY: value lines (Robot Variables files / common.yaml).
_YAML_VAR = re.compile(
    r"^(?P<name>[A-Za-z_][\w.]*)\s*:\s*(?P<value>.+?)\s*$",
)


def _sid(kind: str, file_path: Path, name: str, line: int) -> str:
    raw = f"{kind}:{file_path}:{name}:{line}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:24]


class YamlVariableIndexer:
    """Extracts top-level scalar variables from ``.yaml`` / ``.yml`` files."""

    INDEXABLE_SUFFIXES = {".yaml", ".yml"}

    def index_file(
        self,
        path: Path,
        *,
        workspace_id: UUID | None,
        project_id: UUID | None,
    ) -> tuple[list[IndexedSymbol], list[dict]]:
        text = path.read_text(encoding="utf-8", errors="replace")
        mtime = path.stat().st_mtime
        symbols: list[IndexedSymbol] = []
        for line_no, raw in enumerate(text.splitlines(), start=1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # Skip nested YAML / list items for v1.
            if raw[:1] in {" ", "\t", "-", "["}:
                continue
            match = _YAML_VAR.match(line)
            if not match:
                continue
            name = match.group("name")
            value = match.group("value").strip().strip("'\"")
            # Robot-style ${NAME} alias for search / go-to.
            display = name if name.startswith("${") else f"${{{name}}}"
            symbols.append(
                IndexedSymbol(
                    id=_sid(SymbolKind.VARIABLE.value, path, display, line_no),
                    name=display,
                    kind=SymbolKind.VARIABLE.value,
                    file_path=path,
                    line=line_no,
                    project_id=project_id,
                    workspace_id=workspace_id,
                    documentation="",
                    detail=value[:120],
                    last_modified=mtime,
                ),
            )
            # Also index bare key for BASE_URL-style search.
            if display != name:
                symbols.append(
                    IndexedSymbol(
                        id=_sid(SymbolKind.VARIABLE.value, path, name, line_no),
                        name=name,
                        kind=SymbolKind.VARIABLE.value,
                        file_path=path,
                        line=line_no,
                        project_id=project_id,
                        workspace_id=workspace_id,
                        documentation="",
                        detail=value[:120],
                        last_modified=mtime,
                    ),
                )
        return symbols, []
