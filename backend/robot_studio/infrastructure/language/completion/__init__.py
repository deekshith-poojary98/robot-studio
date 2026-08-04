"""Language completion providers + ranking pipeline."""

from robot_studio.infrastructure.language.completion.buffer_provider import (
    BufferCompletionProvider,
)
from robot_studio.infrastructure.language.completion.dsl_provider import (
    DslCompletionProvider,
    SectionCompletionProvider,
    SettingCompletionProvider,
)
from robot_studio.infrastructure.language.completion.files_provider import (
    FilesCompletionProvider,
)
from robot_studio.infrastructure.language.completion.keyword_provider import (
    IndexSymbolCompletionProvider,
    KeywordCompletionProvider,
    VariableCompletionProvider,
)
from robot_studio.infrastructure.language.completion.named_argument_provider import (
    NamedArgumentCompletionProvider,
    resolve_keyword_via_pipeline,
)
from robot_studio.infrastructure.language.completion.pipeline import CompletionPipeline
from robot_studio.infrastructure.language.completion.ranking import merge_and_rank, rank_score
from robot_studio.infrastructure.language.completion.usage_store import (
    SqliteCompletionUsageStore,
)

__all__ = [
    "BufferCompletionProvider",
    "CompletionPipeline",
    "DslCompletionProvider",
    "FilesCompletionProvider",
    "IndexSymbolCompletionProvider",
    "KeywordCompletionProvider",
    "NamedArgumentCompletionProvider",
    "SectionCompletionProvider",
    "SettingCompletionProvider",
    "SqliteCompletionUsageStore",
    "VariableCompletionProvider",
    "merge_and_rank",
    "rank_score",
    "resolve_keyword_via_pipeline",
]
