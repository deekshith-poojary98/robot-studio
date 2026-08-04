"""Signature Help discovery providers (libdoc + index)."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any

from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.interfaces.signature_help import (
    SignatureHelpProvider,
    SignatureHelpRequestContext,
)
from robot_studio.domain.models.keyword_metadata import (
    KeywordMetadata,
    KeywordSourceType,
    ParameterMetadata,
)
from robot_studio.infrastructure.language.keyword_helpers import (
    parameters_from_detail_string,
    strip_keyword_qualifier,
)

ResolveLibrary = Callable[[str], Awaitable[dict[str, Any]]]
ImportedLibraries = Callable[[str], list[str]]
FindDefinition = Callable[..., Awaitable[dict | None]]


@dataclass
class LibdocSignatureHelpProvider(SignatureHelpProvider):
    """Discover keywords from env libraries / BuiltIn via resolve_library transport."""

    resolve_library: ResolveLibrary
    imported_libraries: ImportedLibraries

    @property
    def provider_id(self) -> str:
        return "libdoc"

    @property
    def priority(self) -> int:
        return 80

    async def resolve(self, ctx: SignatureHelpRequestContext) -> KeywordMetadata | None:
        bare = strip_keyword_qualifier(ctx.keyword)
        keys = {ctx.keyword.casefold(), bare.casefold()}
        # Alias.Keyword — try alias library first
        qualifier = ""
        if "." in ctx.keyword:
            head, _, rest = ctx.keyword.partition(".")
            if rest:
                qualifier = head.strip()
                keys.add(rest.casefold())

        libraries = list(self.imported_libraries(ctx.content))
        if qualifier:
            libraries = [qualifier, *libraries]
        if "BuiltIn" not in libraries:
            libraries.append("BuiltIn")

        for library_name in libraries:
            resolved = await self.resolve_library(library_name)
            if not resolved.get("available"):
                continue
            info_map = resolved.get("keyword_info") or {}
            for key in keys:
                raw = info_map.get(key)
                if not isinstance(raw, dict):
                    continue
                meta = KeywordMetadata.from_transport(raw)
                # Ensure library_name / source_type filled
                lib = meta.library_name or str(resolved.get("name") or library_name)
                source = (
                    KeywordSourceType.BUILTIN
                    if lib.casefold() == "builtin"
                    else KeywordSourceType.LIBRARY
                )
                return KeywordMetadata(
                    name=meta.name or bare,
                    qualified_name=meta.qualified_name or f"{lib}.{meta.name or bare}",
                    source_type=source,
                    library_name=lib,
                    documentation=meta.documentation,
                    parameters=meta.parameters,
                    source_path=meta.source_path,
                    source_line=meta.source_line,
                    deprecated=meta.deprecated,
                    tags=meta.tags,
                    examples=meta.examples,
                    detail=meta.detail,
                )
        return None


@dataclass
class IndexSignatureHelpProvider(SignatureHelpProvider):
    """Discover user / resource keywords from the symbol index."""

    find_definition: FindDefinition

    @property
    def provider_id(self) -> str:
        return "index"

    @property
    def priority(self) -> int:
        return 60

    async def resolve(self, ctx: SignatureHelpRequestContext) -> KeywordMetadata | None:
        bare = strip_keyword_qualifier(ctx.keyword)
        definition = await self.find_definition(bare, kind=SymbolKind.KEYWORD)
        if definition is None and bare != ctx.keyword:
            definition = await self.find_definition(ctx.keyword, kind=SymbolKind.KEYWORD)
        if not definition:
            return None
        detail = str(definition.get("detail") or "")
        params = parameters_from_detail_string(detail)
        # Prefer structured parameters if index already stored them
        raw_params = definition.get("parameters")
        if isinstance(raw_params, list) and raw_params:
            params = tuple(
                ParameterMetadata.from_transport(item)
                for item in raw_params
                if isinstance(item, dict)
            )
        path = str(definition.get("file_path") or "")
        source_type = KeywordSourceType.USER
        if path.endswith(".resource"):
            source_type = KeywordSourceType.RESOURCE
        line = definition.get("line")
        return KeywordMetadata(
            name=str(definition.get("name") or bare),
            qualified_name=str(definition.get("name") or bare),
            source_type=source_type,
            library_name="",
            documentation=str(definition.get("documentation") or ""),
            parameters=params,
            source_path=path,
            source_line=int(line) if line is not None else None,
            detail=detail,
        )
