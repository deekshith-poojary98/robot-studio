"""Document intelligence — nested symbol tree for Outline, breadcrumbs, folding."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterator


@dataclass(frozen=True)
class DocumentSymbol:
    """One node in a Robot document symbol tree (immutable)."""

    name: str
    kind: str
    line: int = 1
    end_line: int | None = None
    column: int = 1
    detail: str = ""
    documentation: str = ""
    children: tuple[DocumentSymbol, ...] = ()
    id: str = ""

    def __post_init__(self) -> None:
        if not self.id:
            object.__setattr__(
                self,
                "id",
                f"{self.kind}:{self.line}:{self.name}",
            )
        if self.end_line is None:
            object.__setattr__(self, "end_line", self.line)

    @property
    def foldable(self) -> bool:
        end = self.end_line or self.line
        return end > self.line and (
            bool(self.children) or self.kind in {"section", "keyword", "test_case", "control"}
        )

    def walk(self) -> Iterator[DocumentSymbol]:
        yield self
        for child in self.children:
            yield from child.walk()

    def find_at_line(self, line: int) -> DocumentSymbol | None:
        """Innermost symbol whose range contains *line*."""
        end = self.end_line or self.line
        if line < self.line or line > end:
            return None
        best: DocumentSymbol | None = self
        for child in self.children:
            hit = child.find_at_line(line)
            if hit is not None:
                best = hit
        return best

    def to_api(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "kind": self.kind,
            "line": self.line,
            "end_line": self.end_line or self.line,
            "column": self.column,
            "detail": self.detail,
            "documentation": self.documentation,
            "children": [child.to_api() for child in self.children],
        }

    @staticmethod
    def from_api(raw: dict[str, Any]) -> DocumentSymbol:
        children = tuple(
            DocumentSymbol.from_api(item)
            for item in (raw.get("children") or [])
            if isinstance(item, dict)
        )
        return DocumentSymbol(
            name=str(raw.get("name") or ""),
            kind=str(raw.get("kind") or "symbol"),
            line=int(raw.get("line") or 1),
            end_line=int(raw.get("end_line") or raw.get("line") or 1),
            column=int(raw.get("column") or 1),
            detail=str(raw.get("detail") or ""),
            documentation=str(raw.get("documentation") or ""),
            children=children,
            id=str(raw.get("id") or ""),
        )


@dataclass(frozen=True)
class DocumentSymbolTree:
    """Complete symbol tree for one Robot / resource file."""

    file_path: str
    root: DocumentSymbol
    content_hash: str = ""

    def flatten(self) -> list[DocumentSymbol]:
        return list(self.root.walk())

    def active_symbol(self, line: int) -> DocumentSymbol | None:
        return self.root.find_at_line(line)

    def folding_ranges(self) -> list[dict[str, int]]:
        """0-based inclusive line ranges for editor folding."""
        ranges: list[dict[str, int]] = []
        for node in self.flatten():
            if not node.foldable:
                continue
            start = max(0, node.line - 1)
            end = max(start, (node.end_line or node.line) - 1)
            if end > start:
                ranges.append({"start_line": start, "end_line": end})
        # Prefer outer ranges first for chunk analyzers
        ranges.sort(key=lambda r: (r["start_line"], -r["end_line"]))
        return ranges

    def filter(self, query: str) -> DocumentSymbolTree:
        """Return a new tree keeping nodes that match *query* (and their ancestors)."""
        needle = (query or "").strip().casefold()
        if not needle:
            return self

        def keep(node: DocumentSymbol) -> DocumentSymbol | None:
            kept_children = tuple(
                c for child in node.children if (c := keep(child)) is not None
            )
            self_match = needle in node.name.casefold() or needle in node.detail.casefold()
            if self_match or kept_children:
                return DocumentSymbol(
                    name=node.name,
                    kind=node.kind,
                    line=node.line,
                    end_line=node.end_line,
                    column=node.column,
                    detail=node.detail,
                    documentation=node.documentation,
                    children=kept_children,
                    id=node.id,
                )
            return None

        new_root = keep(self.root)
        if new_root is None:
            new_root = DocumentSymbol(
                name=self.root.name,
                kind=self.root.kind,
                line=self.root.line,
                end_line=self.root.end_line,
                children=(),
                id=self.root.id,
            )
        return DocumentSymbolTree(
            file_path=self.file_path,
            root=new_root,
            content_hash=self.content_hash,
        )

    def to_api(self) -> dict[str, Any]:
        return {
            "file_path": self.file_path,
            "content_hash": self.content_hash,
            "root": self.root.to_api(),
            "folding_ranges": self.folding_ranges(),
        }

    @staticmethod
    def from_api(raw: dict[str, Any]) -> DocumentSymbolTree:
        root_raw = raw.get("root") or {}
        return DocumentSymbolTree(
            file_path=str(raw.get("file_path") or ""),
            root=DocumentSymbol.from_api(root_raw if isinstance(root_raw, dict) else {}),
            content_hash=str(raw.get("content_hash") or ""),
        )
