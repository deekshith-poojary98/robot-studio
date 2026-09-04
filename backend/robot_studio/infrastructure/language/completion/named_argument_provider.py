"""Named-argument completion from KeywordMetadata."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from robot_studio.domain.interfaces.completion import (
    CompletionCandidate,
    CompletionProvider,
    CompletionRequestContext,
    match_score,
    matches_prefix,
)
from robot_studio.domain.interfaces.signature_help import (
    SignatureHelpPipeline,
    SignatureHelpRequestContext,
)
from robot_studio.domain.models.keyword_metadata import KeywordMetadata
from robot_studio.infrastructure.language.keyword_helpers import (
    is_typing_argument_value,
    parameter_completion_score,
    parse_argument_cell,
    present_named_args,
    strip_keyword_qualifier,
)

ResolveKeyword = Callable[[SignatureHelpRequestContext], Awaitable[KeywordMetadata | None]]


@dataclass
class NamedArgumentCompletionProvider(CompletionProvider):
    """Offer ``name=`` inserts for the resolved keyword at an argument site."""

    resolve_keyword: ResolveKeyword

    @property
    def provider_id(self) -> str:
        return "named_arguments"

    @property
    def label(self) -> str:
        return "Parameters"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"argument"})

    @property
    def base_priority(self) -> int:
        return 95

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        keyword = (ctx.keyword or "").strip()
        if not keyword:
            return []
        meta = await self.resolve_keyword(
            SignatureHelpRequestContext(
                file_path=ctx.file_path,
                content=ctx.content,
                line=ctx.line,
                column=ctx.column,
                keyword=keyword,
                arguments=tuple(ctx.arguments),
                active_parameter_hint=0,
                project_id=ctx.project_id,
            ),
        )
        if meta is None or not meta.parameters:
            return []
        if is_typing_argument_value(ctx.current_argument):
            return []

        already = present_named_args(list(ctx.arguments))
        positional_used = sum(
            1
            for cell in ctx.arguments
            if cell.strip() and parse_argument_cell(cell)[0] is None
        )
        prefix = ctx.prefix
        # Allow typing ``browser`` or ``browser=``
        prefix_name = prefix.rstrip("=")

        skipped_positional = 0
        items: list[CompletionCandidate] = []
        for index, param in enumerate(meta.parameters):
            if param.kind in {"var_positional"}:
                continue
            if param.name.casefold() in already:
                continue
            keyword_only = param.kind in {"keyword_only", "var_keyword"}
            if not keyword_only and skipped_positional < positional_used:
                skipped_positional += 1
                continue
            insert = f"{param.name}="
            label = insert
            if not matches_prefix(param.name, prefix_name) and not matches_prefix(
                insert,
                prefix,
            ):
                continue
            required = "required" if param.required else "optional"
            default_bit = f" · {param.default}" if param.default is not None else ""
            score = parameter_completion_score(
                param,
                keyword_name=strip_keyword_qualifier(meta.name),
                prefix=prefix_name,
            )
            if index == ctx.active_parameter:
                score += 40
            items.append(
                CompletionCandidate(
                    label=label,
                    kind="parameter",
                    detail=f"{required}{default_bit}",
                    documentation=param.documentation or meta.documentation,
                    insert_text=insert,
                    provider_id=self.provider_id,
                    match_score=match_score(param.name, prefix_name) + score / 100.0,
                    base_priority=self.base_priority,
                ),
            )
        items.sort(key=lambda c: c.match_score, reverse=True)
        return items


def resolve_keyword_via_pipeline(
    pipeline: SignatureHelpPipeline,
) -> ResolveKeyword:
    async def _resolve(ctx: SignatureHelpRequestContext) -> KeywordMetadata | None:
        return await pipeline.resolve(ctx)

    return _resolve
