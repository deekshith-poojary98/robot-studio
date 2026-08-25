"""Python buffer + index + Jedi language intelligence (tiers 1–3)."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import pytest

from robot_studio.domain.interfaces.completion import CompletionRequestContext
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.infrastructure.indexing.python_indexer import PythonLibraryIndexer
from robot_studio.infrastructure.language.completion.python_provider import (
    PythonBufferCompletionProvider,
    PythonIndexCompletionProvider,
    PythonJediCompletionProvider,
)
from robot_studio.infrastructure.language.python_jedi import (
    jedi_available,
    jedi_completions,
    jedi_definitions,
    jedi_signature_help,
)
from robot_studio.infrastructure.language.python_language import (
    python_buffer_completions,
    python_completion_context,
    python_signature_help,
)


SAMPLE = """\
BASE_URL = "https://example.com"

class Client:
    timeout: int = 30

    def __init__(self, host: str):
        self.host = host

    def get_user(self, user_id: int, *, verbose: bool = False):
        \"\"\"Fetch one user.\"\"\"
        return user_id

def helper(name: str) -> str:
    return name
"""


def test_python_completion_context_ident_and_attr() -> None:
    assert python_completion_context(SAMPLE, 1, 5)["prefix"] == "BASE"
    assert python_completion_context(SAMPLE, 1, 5)["context"] == "python"

    line = next(
        i for i, row in enumerate(SAMPLE.splitlines(), start=1) if "return user_id" in row
    )
    content = SAMPLE.replace("        return user_id", "        self.\n        return user_id")
    ctx = python_completion_context(content, line, 14)
    assert ctx["context"] == "python_attr"
    assert ctx["attribute_base"] == "self"
    assert ctx["prefix"] == ""

    content2 = SAMPLE.replace("        return user_id", "        self.ge\n        return user_id")
    ctx2 = python_completion_context(content2, line, 16)
    assert ctx2["context"] == "python_attr"
    assert ctx2["attribute_base"] == "self"
    assert ctx2["prefix"] == "ge"


def test_python_buffer_completions_defs_and_self() -> None:
    items = python_buffer_completions(
        SAMPLE,
        line=1,
        column=1,
        prefix="hel",
        context="python",
    )
    assert any(i["label"] == "helper" for i in items)

    items2 = python_buffer_completions(
        SAMPLE,
        line=1,
        column=1,
        prefix="Cli",
        context="python",
    )
    assert any(i["label"] == "Client" for i in items2)

    content = SAMPLE.replace("        return user_id", "        self.\n        return user_id")
    line = next(i for i, row in enumerate(content.splitlines(), start=1) if row.strip() == "self.")
    attrs = python_buffer_completions(
        content,
        line=line,
        column=14,
        prefix="",
        context="python_attr",
        attribute_base="self",
    )
    labels = {i["label"] for i in attrs}
    assert "get_user" in labels
    assert "__init__" in labels


def test_python_signature_help_from_call() -> None:
    content = SAMPLE + "\n\nc = Client('h')\nr = c.get_user(1, verbose=False)\n"
    line = len(content.splitlines())  # the get_user line
    # Caret after ``1, ``
    col = content.splitlines()[line - 1].index("1,") + 3
    help_ = python_signature_help(content, line, col)
    assert help_ is not None
    assert help_["keyword"] == "get_user"
    names = [p["name"] for p in help_["parameters"]]
    assert names == ["user_id", "verbose"]
    assert help_["active_parameter"] == 1


def test_python_indexer_emits_snake_case_and_class() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "client_lib.py"
        path.write_text(SAMPLE, encoding="utf-8")
        symbols = PythonLibraryIndexer().index_file(path, workspace_id=None, project_id=None)

    kinds = {(s.kind, s.name) for s in symbols}
    assert (SymbolKind.LIBRARY.value, "Client") in kinds
    assert (SymbolKind.LIBRARY.value, "client_lib") in kinds
    assert (SymbolKind.KEYWORD.value, "get_user") in kinds
    assert (SymbolKind.KEYWORD.value, "helper") in kinds
    assert (SymbolKind.VARIABLE.value, "BASE_URL") in kinds
    assert (SymbolKind.KEYWORD.value, "get user") in kinds


async def test_python_buffer_provider_accepts_py_only() -> None:
    provider = PythonBufferCompletionProvider()
    ctx = CompletionRequestContext(
        file_path="/proj/lib.py",
        content=SAMPLE,
        line=1,
        column=4,
        prefix="BAS",
        context="python",
    )
    items = await provider.complete(ctx)
    assert any(i.label == "BASE_URL" for i in items)

    robot_ctx = CompletionRequestContext(
        file_path="/proj/suite.robot",
        content="*** Test Cases ***\n",
        line=1,
        column=1,
        prefix="Log",
        context="python",
    )
    assert provider.accepts(robot_ctx) is False


async def test_python_index_provider_filters_py_paths() -> None:
    async def search_symbols(prefix: str, kind=None, limit: int = 60):  # noqa: ANN001
        return [
            {
                "name": "shared_helper",
                "kind": SymbolKind.KEYWORD.value,
                "file_path": "/ws/libs/shared.py",
                "detail": "python",
                "documentation": "",
            },
            {
                "name": "Robot Keyword",
                "kind": SymbolKind.KEYWORD.value,
                "file_path": "/ws/suite.robot",
                "detail": "",
                "documentation": "",
            },
        ]

    provider = PythonIndexCompletionProvider(search_symbols=search_symbols)
    ctx = CompletionRequestContext(
        file_path="/ws/other.py",
        content="",
        line=1,
        column=1,
        prefix="sha",
        context="python",
    )
    items = await provider.complete(ctx)
    labels = [i.label for i in items]
    assert "shared_helper" in labels
    assert not any("Robot" in label for label in labels)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_jedi_completions_stdlib_json() -> None:
    content = "import json\njson."
    line = 2
    column = len("json.") + 1  # 1-based, after dot
    items = jedi_completions(
        content,
        "module.py",
        line,
        column,
        Path(sys.executable),
        None,
    )
    labels = {item["label"] for item in items}
    assert "dumps" in labels
    assert "loads" in labels


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_jedi_signature_help_stdlib_json() -> None:
    content = "import json\njson.dumps(1, "
    line = 2
    column = len("json.dumps(1, ")  # 1-based at trailing space
    help_ = jedi_signature_help(
        content,
        "module.py",
        line,
        column,
        Path(sys.executable),
        None,
    )
    assert help_ is not None
    assert help_["keyword"] == "dumps"
    assert any(p["name"] == "obj" for p in help_["parameters"])
    assert help_["active_parameter"] >= 1


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_jedi_definitions_stdlib_json() -> None:
    content = "import json\njson.dumps"
    line = 2
    column = len("json.dumps")  # 1-based end of symbol
    defs = jedi_definitions(
        content,
        "module.py",
        line,
        column,
        Path(sys.executable),
        None,
    )
    assert defs
    assert defs[0]["name"] == "dumps"
    assert defs[0]["file_path"].endswith("json/__init__.py") or "json" in defs[0]["file_path"]


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
async def test_python_jedi_provider_completes() -> None:
    provider = PythonJediCompletionProvider(
        resolve_python=lambda: Path(sys.executable),
        resolve_project_root=lambda: None,
    )
    ctx = CompletionRequestContext(
        file_path="/proj/module.py",
        content="import json\njson.",
        line=2,
        column=len("json.") + 1,
        prefix="",
        context="python_attr",
        attribute_base="json",
    )
    items = await provider.complete(ctx)
    assert any(item.label == "dumps" for item in items)
