"""DSL / section / setting completion providers."""

from __future__ import annotations

from robot_studio.domain.interfaces.completion import (
    CompletionCandidate,
    CompletionProvider,
    CompletionRequestContext,
    match_score,
    matches_prefix,
)
from robot_studio.infrastructure.language.builtin_keywords import (
    CONTROL_STRUCTURES,
    LOCAL_SETTINGS,
    SECTION_HEADERS,
    SETTING_NAMES,
)


class SectionCompletionProvider(CompletionProvider):
    @property
    def provider_id(self) -> str:
        return "sections"

    @property
    def label(self) -> str:
        return "Sections"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"section"})

    @property
    def base_priority(self) -> int:
        return 90

    def accepts(self, ctx: CompletionRequestContext) -> bool:
        if ctx.prefix.startswith("*"):
            return True
        return super().accepts(ctx)

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        if not (ctx.prefix.startswith("*") or ctx.context == "section"):
            return []
        out: list[CompletionCandidate] = []
        for header in SECTION_HEADERS:
            if matches_prefix(header, ctx.prefix):
                out.append(
                    CompletionCandidate(
                        label=header,
                        kind="section",
                        detail="Section header",
                        insert_text=header,
                        provider_id=self.provider_id,
                        match_score=match_score(header, ctx.prefix),
                        base_priority=self.base_priority,
                    ),
                )
        return out


class SettingCompletionProvider(CompletionProvider):
    @property
    def provider_id(self) -> str:
        return "settings"

    @property
    def label(self) -> str:
        return "Settings"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"setting", "library", "resource", "local_setting"})

    @property
    def base_priority(self) -> int:
        return 85

    def accepts(self, ctx: CompletionRequestContext) -> bool:
        # Local settings like ``[Doc`` may still report keyword_call context.
        if ctx.prefix.startswith("["):
            return True
        return super().accepts(ctx)

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        out: list[CompletionCandidate] = []
        if ctx.context == "local_setting" or ctx.prefix.startswith("["):
            for name in LOCAL_SETTINGS:
                if matches_prefix(name, ctx.prefix):
                    out.append(
                        CompletionCandidate(
                            label=name,
                            kind="setting",
                            detail="Local setting",
                            insert_text=name,
                            provider_id=self.provider_id,
                            match_score=match_score(name, ctx.prefix),
                            base_priority=self.base_priority,
                        ),
                    )
        if ctx.context in {"setting", "library", "resource"} or ctx.section == "settings":
            for name in SETTING_NAMES:
                if matches_prefix(name, ctx.prefix):
                    out.append(
                        CompletionCandidate(
                            label=name,
                            kind="setting",
                            detail="Suite setting",
                            insert_text=name,
                            provider_id=self.provider_id,
                            match_score=match_score(name, ctx.prefix),
                            base_priority=self.base_priority,
                        ),
                    )
        return out


class DslCompletionProvider(CompletionProvider):
    @property
    def provider_id(self) -> str:
        return "dsl"

    @property
    def label(self) -> str:
        return "RF DSL"

    @property
    def supported_contexts(self) -> frozenset[str]:
        return frozenset({"library", "keyword_call", "keyword", "control"})

    @property
    def base_priority(self) -> int:
        return 80

    async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
        out: list[CompletionCandidate] = []
        for marker in CONTROL_STRUCTURES:
            label = str(marker["label"])
            if matches_prefix(label, ctx.prefix):
                out.append(
                    CompletionCandidate(
                        label=label,
                        kind="dsl",
                        detail=str(marker.get("detail") or "RF DSL"),
                        documentation=str(marker.get("documentation") or ""),
                        insert_text=str(marker.get("insert_text") or label),
                        provider_id=self.provider_id,
                        match_score=match_score(label, ctx.prefix),
                        base_priority=self.base_priority,
                    ),
                )
        return out
