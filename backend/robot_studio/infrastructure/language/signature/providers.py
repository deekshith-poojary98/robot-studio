"""Signature Help discovery providers (catalog + index)."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass

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
from robot_studio.infrastructure.language.library_catalog import LibraryCatalogService

FindDefinition = Callable[..., Awaitable[dict | None]]
ImportedLibraries = Callable[..., list[str]]


@dataclass
class LibdocSignatureHelpProvider(SignatureHelpProvider):
    """Discover keywords via LibraryCatalogService (never resolve_library directly)."""

    catalog: LibraryCatalogService
    imported_libraries: ImportedLibraries

    @property
    def provider_id(self) -> str:
        return "libdoc"

    @property
    def priority(self) -> int:
        return 80

    async def resolve(self, ctx: SignatureHelpRequestContext) -> KeywordMetadata | None:
        libraries = list(self.imported_libraries(ctx.content, ctx.file_path))
        found = await self.catalog.find_keyword(ctx.keyword, libraries=libraries)
        if found is not None:
            return found
        bare = strip_keyword_qualifier(ctx.keyword)
        if bare != ctx.keyword:
            return await self.catalog.find_keyword(bare, libraries=libraries)
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
