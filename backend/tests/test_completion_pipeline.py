"""Unit tests for completion providers, ranking, and usage boosts."""

from __future__ import annotations

from pathlib import Path

import pytest
from robot_studio.domain.interfaces.completion import (
    CompletionCandidate,
    CompletionRequestContext,
    match_score,
    matches_prefix,
)
from robot_studio.infrastructure.language.completion.buffer_provider import (
    BufferCompletionProvider,
)
from robot_studio.infrastructure.language.completion.dsl_provider import (
    DslCompletionProvider,
)
from robot_studio.infrastructure.language.completion.pipeline import CompletionPipeline
from robot_studio.infrastructure.language.completion.ranking import (
    merge_and_rank,
    rank_score,
)
from robot_studio.infrastructure.language.completion.usage_store import (
    SqliteCompletionUsageStore,
)


def test_matches_prefix_is_word_start_not_substring() -> None:
    assert matches_prefix("Add Two Numbers", "A")
    assert matches_prefix("Add Two Numbers", "Two")
    assert not matches_prefix("FOR", "A")
    assert not matches_prefix("RANGE", "A")
    assert match_score("Log", "Log") > match_score("Log To Console", "Log")


@pytest.mark.asyncio
async def test_buffer_provider_mines_variables_and_keywords() -> None:
    content = """*** Keywords ***
Login User
    ${user}=    Set Variable    alice
    Log    ${user}
    Log    alice

*** Test Cases ***
Demo
    Login User
    Login User
"""
    kw_ctx = CompletionRequestContext(
        file_path="demo.robot",
        content=content,
        line=8,
        column=6,
        prefix="Log",
        context="keyword_call",
        section="test cases",
    )
    kw_items = await BufferCompletionProvider().complete(kw_ctx)
    kw_labels = {item.label for item in kw_items}
    assert "Login User" in kw_labels
    # Exact echo of the typed prefix is suppressed.
    assert "Log" not in kw_labels
    login = next(item for item in kw_items if item.label == "Login User")
    assert login.buffer_frequency >= 2
    assert login.provider_id == "buffer"

    var_ctx = CompletionRequestContext(
        file_path="demo.robot",
        content=content,
        line=4,
        column=10,
        prefix="${u",
        context="variable",
        section="keywords",
    )
    var_items = await BufferCompletionProvider().complete(var_ctx)
    var_labels = {item.label for item in var_items}
    assert "${user}" in var_labels


@pytest.mark.asyncio
async def test_buffer_provider_skips_documentation_and_local_settings() -> None:
    content = """*** Keywords ***
Click Element
    [Documentation]    Doc: Perform click action
    [Tags]    smoke
    Click
"""
    ctx = CompletionRequestContext(
        file_path="demo.robot",
        content=content,
        line=5,
        column=10,
        prefix="C",
        context="keyword_call",
        section="keywords",
    )
    items = await BufferCompletionProvider().complete(ctx)
    labels = {item.label for item in items}
    assert "Click Element" in labels
    assert "Doc: Perform click action" not in labels
    assert "smoke" not in labels


@pytest.mark.asyncio
async def test_dsl_provider_context_aware_and_prefix() -> None:
    provider = DslCompletionProvider()
    for_ctx = CompletionRequestContext(
        file_path="x.robot",
        content="",
        line=1,
        column=1,
        prefix="FO",
        context="keyword_call",
    )
    items = await provider.complete(for_ctx)
    assert any(item.label == "FOR" for item in items)

    letter_a = CompletionRequestContext(
        file_path="x.robot",
        content="",
        line=1,
        column=1,
        prefix="A",
        context="keyword_call",
    )
    a_items = await provider.complete(letter_a)
    labels = {item.label for item in a_items}
    assert "FOR" not in labels
    assert "IF" not in labels


@pytest.mark.asyncio
async def test_pipeline_excludes_robot_providers_for_python_files() -> None:
    from robot_studio.infrastructure.language.completion.python_provider import (
        PythonBufferCompletionProvider,
    )

    ctx = CompletionRequestContext(
        file_path="/proj/test.py",
        content="i",
        line=1,
        column=2,
        prefix="i",
        context="python",
        section="python",
    )
    pipe = CompletionPipeline(
        providers=[PythonBufferCompletionProvider(), DslCompletionProvider()],
    )
    ranked = await pipe.complete(ctx, limit=50)
    providers = {item.provider_id for item in ranked}
    assert providers <= {"python_buffer"}
    assert not any("FOR" in item.label for item in ranked)


def test_merge_and_rank_prefers_usage_and_buffer() -> None:
    a = CompletionCandidate(
        label="Log",
        kind="keyword",
        match_score=2.0,
        usage_count=0,
        buffer_frequency=0,
        base_priority=60,
        provider_id="keywords",
    )
    b = CompletionCandidate(
        label="Log",
        kind="keyword",
        match_score=2.0,
        usage_count=5,
        buffer_frequency=3,
        base_priority=70,
        provider_id="buffer",
    )
    ranked = merge_and_rank([[a], [b]], limit=10)
    assert len(ranked) == 1
    assert ranked[0].provider_id == "buffer"
    assert rank_score(b) > rank_score(a)


@pytest.mark.asyncio
async def test_pipeline_applies_usage_boost(tmp_path: Path) -> None:
    store = SqliteCompletionUsageStore(tmp_path / "usage.db")
    await store.ensure_schema()
    await store.record(project_id="proj-1", label="Should Be Equal", kind="keyword")
    await store.record(project_id="proj-1", label="Should Be Equal", kind="keyword")

    class _StaticProvider:
        provider_id = "keywords"
        label = "Keywords"
        supported_contexts = frozenset()
        base_priority = 50

        def accepts(self, ctx: CompletionRequestContext) -> bool:
            return True

        async def complete(self, ctx: CompletionRequestContext) -> list[CompletionCandidate]:
            return [
                CompletionCandidate(
                    label="Should Be Equal",
                    kind="keyword",
                    match_score=2.0,
                    base_priority=50,
                    provider_id="keywords",
                ),
                CompletionCandidate(
                    label="Should Be True",
                    kind="keyword",
                    match_score=2.0,
                    base_priority=50,
                    provider_id="keywords",
                ),
            ]

    pipeline = CompletionPipeline(providers=[_StaticProvider()], usage_store=store)  # type: ignore[arg-type]
    ranked = await pipeline.complete(
        CompletionRequestContext(
            file_path="x.robot",
            content="",
            line=1,
            column=1,
            prefix="Should",
            context="keyword_call",
            project_id="proj-1",
        ),
    )
    assert ranked[0].label == "Should Be Equal"
    assert ranked[0].usage_count == 2
