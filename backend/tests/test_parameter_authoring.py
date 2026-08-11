"""Unit tests for KeywordMetadata, parameter helpers, and signature pipeline merge."""

from __future__ import annotations

import pytest

from robot_studio.domain.interfaces.signature_help import (
    SignatureHelpPipeline,
    SignatureHelpProvider,
    SignatureHelpRequestContext,
)
from robot_studio.domain.models.keyword_metadata import (
    KeywordMetadata,
    KeywordSourceType,
    ParameterMetadata,
    merge_keyword_metadata,
)
from robot_studio.infrastructure.language.completion.named_argument_provider import (
    NamedArgumentCompletionProvider,
)
from robot_studio.domain.interfaces.completion import CompletionRequestContext
from robot_studio.infrastructure.language.keyword_helpers import (
    active_parameter_index,
    is_typing_argument_value,
    parameter_completion_score,
    present_named_args,
    strip_keyword_qualifier,
)
from robot_studio.infrastructure.language.robot_parsing_worker import (
    completion_context,
    signature_help,
)


def test_parameter_and_keyword_round_trip() -> None:
    meta = KeywordMetadata(
        name="Open Browser",
        qualified_name="SeleniumLibrary.Open Browser",
        source_type=KeywordSourceType.LIBRARY,
        library_name="SeleniumLibrary",
        documentation="Opens a browser.",
        parameters=(
            ParameterMetadata(name="url", required=True),
            ParameterMetadata(name="browser", default="chrome", required=False),
        ),
    )
    restored = KeywordMetadata.from_transport(meta.to_transport())
    assert restored.name == "Open Browser"
    assert restored.parameters[1].default == "chrome"
    api = restored.to_signature_api(active_parameter=1)
    assert api["active_parameter"] == 1
    assert api["parameters"][0]["name"] == "url"
    assert api["parameters"][0]["required"] is True


def test_merge_keyword_metadata_composes_providers() -> None:
    libdoc = KeywordMetadata(
        name="Login",
        source_type=KeywordSourceType.LIBRARY,
        library_name="AuthLib",
        documentation="",
        parameters=(
            ParameterMetadata(name="user", required=True),
            ParameterMetadata(name="password", required=True),
        ),
    )
    index = KeywordMetadata(
        name="Login",
        source_type=KeywordSourceType.USER,
        documentation="Logs the user in.",
        source_path="/proj/keywords.robot",
        source_line=12,
        parameters=(),
    )
    merged = merge_keyword_metadata(libdoc, index)
    assert merged is not None
    assert len(merged.parameters) == 2
    assert merged.documentation == "Logs the user in."
    assert merged.source_path.endswith("keywords.robot")


def test_active_parameter_respects_named_args() -> None:
    meta = KeywordMetadata(
        name="Open Browser",
        parameters=(
            ParameterMetadata(name="url", required=True),
            ParameterMetadata(name="browser", default="chrome", required=False),
            ParameterMetadata(name="alias", default=None, required=False),
        ),
    )
    assert active_parameter_index(meta, arguments=["browser=firefox"], active_hint=0) == 0
    assert (
        active_parameter_index(
            meta,
            arguments=["https://x", "browser=firefox"],
            active_hint=2,
        )
        == 2
    )


def test_parameter_score_prefers_popular_required() -> None:
    url = ParameterMetadata(name="url", required=True)
    options = ParameterMetadata(name="options", required=False, default=None)
    assert parameter_completion_score(url, keyword_name="Open Browser") > parameter_completion_score(
        options,
        keyword_name="Open Browser",
    )


def test_strip_qualifier() -> None:
    assert strip_keyword_qualifier("BuiltIn.Log") == "Log"
    assert strip_keyword_qualifier("Col.Append To List") == "Append To List"


def test_completion_prefix_is_current_argument_cell() -> None:
    content = """*** Test Cases ***
Demo
    Evaluate    expression=random.randint(1,10)    modules=random    name
"""
    row = content.splitlines()[2]
    ctx = completion_context(content, "x.robot", 3, len(row) + 1)
    assert ctx["context"] == "argument"
    assert ctx["prefix"] == "name"
    assert ctx["keyword"] == "Evaluate"


def test_completion_context_argument_after_keyword() -> None:
    content = """*** Test Cases ***
Demo
    Open Browser    
"""
    # Column past trailing spaces after keyword
    row = content.splitlines()[2]
    col = len(row) + 1
    ctx = completion_context(content, "x.robot", 3, col)
    assert ctx["context"] == "argument"
    assert ctx["keyword"] == "Open Browser"


def test_signature_help_continuation() -> None:
    content = """*** Test Cases ***
Demo
    Open Browser    https://example.com
    ...    browser=chrome
"""
    # Caret on continuation row after ...
    row = content.splitlines()[3]
    col = row.index("browser") + 1
    parsed = signature_help(content, "x.robot", 4, col)
    assert parsed is not None
    assert parsed["keyword"] == "Open Browser"


@pytest.mark.asyncio
async def test_signature_pipeline_merges_two_providers() -> None:
    class _A(SignatureHelpProvider):
        provider_id = "a"
        priority = 80

        async def resolve(self, ctx: SignatureHelpRequestContext) -> KeywordMetadata | None:
            return KeywordMetadata(
                name=ctx.keyword,
                parameters=(ParameterMetadata(name="url", required=True),),
                library_name="Lib",
                source_type=KeywordSourceType.LIBRARY,
            )

    class _B(SignatureHelpProvider):
        provider_id = "b"
        priority = 40

        async def resolve(self, ctx: SignatureHelpRequestContext) -> KeywordMetadata | None:
            return KeywordMetadata(
                name=ctx.keyword,
                documentation="From index",
                source_path="/x.robot",
                source_type=KeywordSourceType.USER,
            )

    pipe = SignatureHelpPipeline(providers=[_A(), _B()])
    meta = await pipe.resolve(
        SignatureHelpRequestContext(
            file_path="x.robot",
            content="",
            line=1,
            column=1,
            keyword="Open Browser",
        ),
    )
    assert meta is not None
    assert meta.parameters[0].name == "url"
    assert meta.documentation == "From index"
    assert meta.source_path == "/x.robot"


@pytest.mark.asyncio
async def test_named_argument_provider_skips_present_and_ranks() -> None:
    meta = KeywordMetadata(
        name="Open Browser",
        parameters=(
            ParameterMetadata(name="url", required=True),
            ParameterMetadata(name="browser", default="chrome", required=False),
            ParameterMetadata(name="options", required=False),
        ),
    )

    async def resolve(_ctx):  # noqa: ANN001
        return meta

    provider = NamedArgumentCompletionProvider(resolve_keyword=resolve)
    items = await provider.complete(
        CompletionRequestContext(
            file_path="x.robot",
            content="",
            line=1,
            column=1,
            prefix="",
            context="argument",
            keyword="Open Browser",
            arguments=("browser=firefox",),
        ),
    )
    labels = [i.label for i in items]
    assert "browser=" not in labels
    assert "url=" in labels
    assert labels[0] == "url="
    assert present_named_args(["browser=firefox"]) == {"browser"}


@pytest.mark.asyncio
async def test_named_argument_provider_skips_positional_and_boosts_active() -> None:
    meta = KeywordMetadata(
        name="Evaluate",
        parameters=(
            ParameterMetadata(name="expression", required=True),
            ParameterMetadata(name="modules", required=False),
            ParameterMetadata(name="namespace", required=False),
        ),
    )

    async def resolve(_ctx):  # noqa: ANN001
        return meta

    provider = NamedArgumentCompletionProvider(resolve_keyword=resolve)
    items = await provider.complete(
        CompletionRequestContext(
            file_path="x.robot",
            content="",
            line=1,
            column=1,
            prefix="",
            context="argument",
            keyword="Evaluate",
            arguments=("int(1, 10)",),
            active_parameter=1,
        ),
    )
    labels = [i.label for i in items]
    assert "expression=" not in labels
    assert labels[0] == "modules="
    assert "namespace=" in labels


def test_signature_stays_on_named_value_being_typed() -> None:
    content = """*** Test Cases ***
Demo
    ${num}=    Evaluate    expression=random.randint(
"""
    row = content.splitlines()[2]
    parsed = signature_help(content, "x.robot", 3, len(row) + 1)
    assert parsed is not None
    assert parsed["keyword"] == "Evaluate"
    assert parsed["active_parameter"] == 0
    assert parsed["current_argument"].startswith("expression=")
    assert parsed["arguments_completed"] == []

    after = f"{row}    "
    content_next = "\n".join([*content.splitlines()[:2], after, ""])
    parsed_next = signature_help(content_next, "x.robot", 3, len(after) + 1)
    assert parsed_next is not None
    assert parsed_next["active_parameter"] == 1
    assert parsed_next["current_argument"] == ""


def test_is_typing_argument_value() -> None:
    assert is_typing_argument_value("expression=random.randint(")
    assert is_typing_argument_value("random.randint(")
    assert is_typing_argument_value("modules=")
    assert not is_typing_argument_value("modules")
    assert not is_typing_argument_value("")


@pytest.mark.asyncio
async def test_named_argument_provider_silent_inside_value() -> None:
    meta = KeywordMetadata(
        name="Evaluate",
        parameters=(
            ParameterMetadata(name="expression", required=True),
            ParameterMetadata(name="modules", required=False),
            ParameterMetadata(name="namespace", required=False),
        ),
    )

    async def resolve(_ctx):  # noqa: ANN001
        return meta

    provider = NamedArgumentCompletionProvider(resolve_keyword=resolve)
    items = await provider.complete(
        CompletionRequestContext(
            file_path="x.robot",
            content="",
            line=1,
            column=1,
            prefix="",
            context="argument",
            keyword="Evaluate",
            arguments=("expression=random.randint(",),
            current_argument="expression=random.randint(",
        ),
    )
    assert items == []
