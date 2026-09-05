"""Source-agnostic keyword / parameter metadata for the language subsystem.

Describes a Robot Framework keyword regardless of discovery path
(BuiltIn, libdoc library, user/resource, remote, plugin). Providers only
populate these models; Signature Help, Hover, Completion, and Library Explorer
consume them. Never invent a parallel keyword model or call libdoc from UI paths.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any


def bare_parameter_name(raw: str) -> str:
    """RF ``${locator}`` / ``@{items}`` → ``locator`` / ``items`` (libdoc style)."""
    text = (raw or "").strip()
    if not text:
        return ""
    if "=" in text:
        text = text.split("=", 1)[0].strip()
    if ":" in text:
        text = text.split(":", 1)[0].strip()
    if len(text) >= 4 and text[0] in "$@&%" and text[1] == "{" and text.endswith("}"):
        inner = text[2:-1].strip()
        if inner:
            return inner
    return text


def python_style_parameter_label(
    raw: str = "",
    *,
    name: str = "",
    default: str | None = None,
    type_name: str = "",
) -> str:
    """Rebuild a parameter label without ``${}`` wrappers."""
    text = (raw or "").strip()
    parsed_default = default
    parsed_type = type_name
    parsed_name = name
    if text:
        rest = text
        if "=" in rest:
            left, _, right = rest.partition("=")
            rest = left.strip()
            if parsed_default is None:
                parsed_default = right.strip()
        if ":" in rest:
            left, _, right = rest.partition(":")
            rest = left.strip()
            if not parsed_type:
                parsed_type = right.strip()
        parsed_name = bare_parameter_name(rest) or parsed_name
    parsed_name = bare_parameter_name(parsed_name) or parsed_name
    if not parsed_name:
        return text
    base = f"{parsed_name}: {parsed_type}" if parsed_type else parsed_name
    if parsed_default is not None:
        return f"{base}={parsed_default}"
    return base


class KeywordSourceType(str, Enum):
    BUILTIN = "builtin"
    LIBRARY = "library"
    RESOURCE = "resource"
    USER = "user"
    REMOTE = "remote"
    PLUGIN = "plugin"


@dataclass(frozen=True)
class ParameterMetadata:
    """One keyword argument — independent of libdoc / index shape."""

    name: str
    label: str = ""
    default: str | None = None
    required: bool = True
    kind: str = "positional_or_named"
    type_name: str = ""
    documentation: str = ""

    def __post_init__(self) -> None:
        bare = bare_parameter_name(self.name)
        if bare and bare != self.name:
            object.__setattr__(self, "name", bare)
        label = self.label
        if not label or "${" in label or "@{" in label or "&{" in label or "%{" in label:
            object.__setattr__(
                self,
                "label",
                python_style_parameter_label(
                    label,
                    name=bare or self.name,
                    default=self.default,
                    type_name=self.type_name,
                )
                or self._default_label(),
            )

    def _default_label(self) -> str:
        base = self.name
        if self.type_name:
            base = f"{base}: {self.type_name}"
        if self.default is not None:
            return f"{base}={self.default}"
        return base

    def to_transport(self) -> dict[str, Any]:
        """Worker / cache JSON (not for REST consumers directly)."""
        return {
            "name": self.name,
            "label": self.label or self._default_label(),
            "default": self.default,
            "required": self.required,
            "kind": self.kind,
            "type_name": self.type_name,
            "documentation": self.documentation,
        }

    def to_api(self) -> dict[str, Any]:
        """REST signature-help parameter DTO."""
        return {
            "name": self.name,
            "label": self.label or self._default_label(),
            "default": self.default,
            "required": self.required,
            "kind": self.kind,
            "documentation": self.documentation,
        }

    @staticmethod
    def from_transport(raw: dict[str, Any]) -> ParameterMetadata:
        name = str(raw.get("name") or "").strip()
        label = str(raw.get("label") or "").strip()
        if not name and label:
            name = label.split("=", 1)[0].split(":", 1)[0].strip()
        default = raw.get("default")
        if default is not None:
            default = str(default)
        required = raw.get("required")
        if required is None:
            required = default is None and not str(raw.get("kind") or "").startswith(
                ("var_", "free"),
            )
        return ParameterMetadata(
            name=name or label,
            label=label or name,
            default=default,
            required=bool(required),
            kind=str(raw.get("kind") or "positional_or_named"),
            type_name=str(raw.get("type_name") or raw.get("type") or ""),
            documentation=str(raw.get("documentation") or ""),
        )


@dataclass(frozen=True)
class KeywordMetadata:
    """A Robot Framework keyword — source-agnostic catalog entry."""

    name: str
    qualified_name: str = ""
    source_type: KeywordSourceType = KeywordSourceType.LIBRARY
    library_name: str = ""
    documentation: str = ""
    #: Markup dialect of :attr:`documentation` (libdoc ``doc_format``).
    doc_format: str = ""
    parameters: tuple[ParameterMetadata, ...] = ()
    source_path: str = ""
    source_line: int | None = None
    deprecated: bool = False
    tags: tuple[str, ...] = ()
    examples: tuple[str, ...] = ()
    detail: str = ""

    def display_name(self) -> str:
        return self.qualified_name or self.name

    def signature_detail(self) -> str:
        if self.parameters:
            return ", ".join(p.label or p.name for p in self.parameters)
        return self.detail

    def to_transport(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "qualified_name": self.qualified_name or self.name,
            "source_type": self.source_type.value,
            "library_name": self.library_name,
            "documentation": self.documentation,
            "doc_format": self.doc_format,
            "parameters": [p.to_transport() for p in self.parameters],
            "source_path": self.source_path,
            "source_line": self.source_line,
            "deprecated": self.deprecated,
            "tags": list(self.tags),
            "examples": list(self.examples),
            "detail": self.signature_detail(),
        }

    def to_signature_api(self, *, active_parameter: int = 0) -> dict[str, Any]:
        params = list(self.parameters)
        active = active_parameter
        if params:
            active = max(0, min(active, len(params) - 1))
        return {
            "keyword": self.display_name(),
            "documentation": self.documentation,
            "detail": self.signature_detail(),
            "active_parameter": active,
            "parameters": [p.to_api() for p in params],
            "source_type": self.source_type.value,
            "library_name": self.library_name,
            "deprecated": self.deprecated,
        }

    @staticmethod
    def from_transport(raw: dict[str, Any]) -> KeywordMetadata:
        source_raw = str(raw.get("source_type") or "library")
        try:
            source_type = KeywordSourceType(source_raw)
        except ValueError:
            source_type = KeywordSourceType.LIBRARY
        params_raw = raw.get("parameters") or []
        parameters = tuple(
            ParameterMetadata.from_transport(item)
            for item in params_raw
            if isinstance(item, dict)
        )
        line = raw.get("source_line")
        return KeywordMetadata(
            name=str(raw.get("name") or ""),
            qualified_name=str(raw.get("qualified_name") or raw.get("name") or ""),
            source_type=source_type,
            library_name=str(raw.get("library_name") or ""),
            documentation=str(raw.get("documentation") or ""),
            doc_format=str(raw.get("doc_format") or "").upper(),
            parameters=parameters,
            source_path=str(raw.get("source_path") or raw.get("file_path") or ""),
            source_line=int(line) if line is not None else None,
            deprecated=bool(raw.get("deprecated") or False),
            tags=tuple(str(t) for t in (raw.get("tags") or [])),
            examples=tuple(str(e) for e in (raw.get("examples") or [])),
            detail=str(raw.get("detail") or ""),
        )


def merge_keyword_metadata(*parts: KeywordMetadata | None) -> KeywordMetadata | None:
    """Compose contributions from multiple discovery providers into one keyword."""
    present = [p for p in parts if p is not None and p.name]
    if not present:
        return None
    primary = max(
        present,
        key=lambda k: (
            len(k.parameters),
            len(k.documentation),
            1 if k.source_path else 0,
            1 if k.library_name else 0,
        ),
    )
    # Parameter map: prefer richer entries by name order from longest list.
    by_name: dict[str, ParameterMetadata] = {}
    order: list[str] = []
    for part in sorted(present, key=lambda k: len(k.parameters), reverse=True):
        for param in part.parameters:
            key = param.name.casefold()
            if key not in by_name:
                by_name[key] = param
                order.append(key)
            else:
                existing = by_name[key]
                by_name[key] = ParameterMetadata(
                    name=existing.name or param.name,
                    label=existing.label or param.label,
                    default=existing.default if existing.default is not None else param.default,
                    required=existing.required if existing.default is not None else param.required,
                    kind=existing.kind if existing.kind != "positional_or_named" else param.kind,
                    type_name=existing.type_name or param.type_name,
                    documentation=existing.documentation or param.documentation,
                )
    parameters = tuple(by_name[k] for k in order) if order else primary.parameters

    # The format must follow whichever part actually supplied the text.
    docs = primary.documentation
    doc_format = primary.doc_format
    if not docs:
        for part in present:
            if part.documentation:
                docs = part.documentation
                doc_format = part.doc_format
                break

    path = primary.source_path
    line = primary.source_line
    if not path:
        for part in present:
            if part.source_path:
                path = part.source_path
                line = part.source_line
                break

    tags: list[str] = []
    seen_tags: set[str] = set()
    for part in present:
        for tag in part.tags:
            folded = tag.casefold()
            if folded not in seen_tags:
                seen_tags.add(folded)
                tags.append(tag)

    examples: list[str] = []
    for part in present:
        for ex in part.examples:
            if ex not in examples:
                examples.append(ex)

    return KeywordMetadata(
        name=primary.name,
        qualified_name=primary.qualified_name or primary.name,
        source_type=primary.source_type,
        library_name=primary.library_name
        or next((p.library_name for p in present if p.library_name), ""),
        documentation=docs,
        doc_format=doc_format,
        parameters=parameters,
        source_path=path,
        source_line=line,
        deprecated=any(p.deprecated for p in present),
        tags=tuple(tags),
        examples=tuple(examples),
        detail=primary.detail,
    )
