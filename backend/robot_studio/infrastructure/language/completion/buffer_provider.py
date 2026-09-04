"""Buffer completions — variables, keywords, identifiers, repeated text in the open file."""

from __future__ import annotations

import re
from collections import Counter

from robot_studio.domain.interfaces.completion import (
    CompletionCandidate,
    CompletionProvider,
    CompletionRequestContext,
    match_score,
    matches_prefix,
)
from robot_studio.infrastructure.language.robot_parsing_worker import split_robot_cells

_VAR_RE = re.compile(r"[\$@&%]\{([^{}\n]+)\}")
_IDENT_RE = re.compile(r"[A-Za-z_][\w]*(?: [A-Za-z_][\w]*){0,4}")
_STOP = frozenset(
    {
        "if",
        "else",
        "end",
        "for",
        "while",
        "try",
        "except",
        "finally",
        "return",
        "and",
        "or",
        "not",
        "in",
        "as",
        "with",
        "name",
        "true",
        "false",
        "none",
        "library",
        "resource",
        "variables",
        "documentation",
        "settings",
        "keywords",
        "test",
        "cases",
        "tasks",
    },
)


class BufferCompletionProvider(CompletionProvider):
    """Mine the current buffer for symbols the user already typed."""

    @property
    def provider_id(self) -> str:
        return "buffer"

    @property
    def label(self) -> str:
        return "Buffer"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset(
            {
                "keyword",
                "keyword_call",
                "variable",
                "control",
                "setting",
                "local_setting",
            },
        )

    @property
    def base_priority(self) -> int:
        return 70

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        content = ctx.content or ""
        if not content.strip():
            return []
        prefix = ctx.prefix
        items: list[CompletionCandidate] = []
        seen: set[str] = set()

        def add(
            label: str,
            kind: str,
            detail: str,
            *,
            freq: int,
            insert: str | None = None,
        ) -> None:
            # Don't echo the token currently being typed.
            if prefix and label.casefold() == prefix.casefold():
                return
            if not matches_prefix(label, prefix):
                return
            key = f"{kind}:{label.casefold()}"
            if key in seen:
                return
            seen.add(key)
            items.append(
                CompletionCandidate(
                    label=label,
                    kind=kind,
                    detail=detail,
                    insert_text=insert or label,
                    provider_id=self.provider_id,
                    match_score=match_score(label, prefix),
                    buffer_frequency=freq,
                    base_priority=self.base_priority,
                ),
            )

        # Variables: ${name}, @{list}, …
        var_counts: Counter[str] = Counter()
        for match in _VAR_RE.finditer(content):
            full = match.group(0)
            var_counts[full] += 1
        for label, freq in var_counts.most_common(80):
            if ctx.context == "variable" or prefix.startswith(("${", "@{", "&{", "%{")) or ctx.context in {"keyword_call", "keyword", "control"}:
                add(label, "variable", "In this file", freq=freq)

        # Suite/user keywords & identifiers from non-comment lines
        word_counts: Counter[str] = Counter()
        for raw in content.splitlines():
            line = raw.strip()
            if not line or line.startswith(("#", "*")):
                continue
            # Local settings — including values: [Documentation]    Doc: …
            if line.startswith("["):
                continue
            # Skip suite settings rows
            head = line.split()[0] if line.split() else ""
            if head in {
                "Library",
                "Resource",
                "Variables",
                "Documentation",
                "Metadata",
                "Suite",
                "Test",
                "Task",
                "Force",
                "Default",
                "Keyword",
            }:
                continue
            # Column-0 names (tests / keywords) and indented calls
            cells = split_robot_cells(line)
            for cell in cells[:2]:
                cell = cell.strip()
                if not cell or cell.startswith(("#", "[", "$", "@", "&", "%")):
                    continue
                if cell.casefold() in _STOP:
                    continue
                if (_IDENT_RE.fullmatch(cell) or " " in cell) and re.match(
                    r"^[A-Za-z_]",
                    cell,
                ):
                    word_counts[cell] += 1

        for label, freq in word_counts.most_common(100):
            if len(label) < 2:
                continue
            kind = "keyword" if " " in label or label[:1].isupper() else "text"
            detail = "In this file" if freq == 1 else f"In this file ×{freq}"
            if ctx.context in {"keyword_call", "keyword", "control"} or (
                ctx.context == "variable" and kind == "text"
            ):
                add(label, kind if kind != "text" else "keyword", detail, freq=freq)
            elif kind == "text" and len(prefix) >= 2:
                add(label, "text", detail, freq=freq)

        # Repeated free-text tokens (quoted strings / bare words ≥3 chars)
        text_counts: Counter[str] = Counter()
        for match in re.finditer(r'"([^"\n]{3,})"|\'([^\'\n]{3,})\'', content):
            token = match.group(1) or match.group(2) or ""
            if token and token.casefold() not in _STOP:
                text_counts[token] += 1
        for label, freq in text_counts.most_common(40):
            if freq < 1 or len(prefix) < 2:
                continue
            if ctx.context in {"keyword_call", "keyword", "control", "setting"}:
                add(label, "text", "Repeated text", freq=freq, insert=label)

        return items
