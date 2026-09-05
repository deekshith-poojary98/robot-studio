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
from robot_studio.infrastructure.language.python_diagnostics import (
    pyflakes_available,
    python_diagnostics,
)
from robot_studio.infrastructure.language.python_jedi import (
    environment_sys_path,
    jedi_available,
    jedi_completions,
    jedi_definitions,
    jedi_hover,
    jedi_references,
    jedi_rename,
    jedi_signature_help,
    jedi_syntax_errors,
)
from robot_studio.infrastructure.language.python_language import (
    is_python_path,
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


def test_python_signature_help_only_on_def_header() -> None:
    content = "class Bank:\n    def __init__(self, name):\n        self.name = name\n"
    header = python_signature_help(content, 2, len("    def __init__(self, name)"))
    assert header is not None
    assert header["keyword"] == "__init__"
    # Inside the body the card would follow the caret over the code the user is
    # writing, so no signature is offered there.
    assert python_signature_help(content, 3, len("        self.name = name") + 1) is None


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
    assert (SymbolKind.VARIABLE.value, "${BASE_URL}") in kinds
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
    async def search_symbols(prefix: str, kind=None, limit: int = 60):
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
def test_jedi_completions_insert_text_is_full_name() -> None:
    content = "impo"
    items = jedi_completions(
        content,
        "module.py",
        1,
        5,
        Path(sys.executable),
        None,
        prefix="impo",
    )
    import_item = next((i for i in items if i["label"] == "import"), None)
    assert import_item is not None
    assert import_item["insert_text"] == "import"
    assert import_item["insert_text"] != "importrt"
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
def test_jedi_hover_builtins() -> None:
    content = 'x = "hello"\nx.split()\nlen(x)\nitems = []\nitems.append(1)\n'
    exe = Path(sys.executable)
    cases = (
        (2, "split", "split"),
        (3, "len", "len"),
        (5, "append", "append"),
    )
    for line, token, name in cases:
        column = content.splitlines()[line - 1].index(token) + 2
        hover = jedi_hover(content, "module.py", line, column, exe, None)
        assert hover is not None, token
        assert hover["name"] == name
        assert hover["documentation"] or hover["detail"]


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


def test_python_path_covers_stub_and_script_suffixes() -> None:
    assert is_python_path("lib/client.py")
    assert is_python_path("lib/client.pyi")
    assert is_python_path("lib/tool.PyW")
    assert not is_python_path("suite.robot")
    assert not is_python_path("notes.txt")


def test_environment_sys_path_stays_inside_the_venv() -> None:
    """A venv's bin/python is a symlink; resolving it must not leak the base env."""
    venv = Path(sys.executable).parent.parent
    site_packages = sorted((venv / "lib").glob("python3*/site-packages"))
    if not site_packages:
        pytest.skip("tests are not running from a venv layout")
    paths = environment_sys_path(Path(sys.executable))
    assert str(site_packages[0]) in paths
    assert paths[0] == str(site_packages[0]), "venv site-packages must win over the base interpreter"


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_jedi_completions_defer_docstrings_beyond_the_visible_rows() -> None:
    """Eager per-item docstrings cost ~350ms for ~190 candidates; cap them."""
    items = jedi_completions(
        "import os\nos.",
        "module.py",
        2,
        len("os.") + 1,
        Path(sys.executable),
        None,
    )
    assert len(items) > 20
    documented = [item for item in items if item["documentation"]]
    assert len(documented) <= 15
    assert all("_jedi_item" not in item for item in items)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_jedi_completions_expose_privates_only_when_asked() -> None:
    hidden = jedi_completions(
        "import os\nos.",
        "module.py",
        2,
        len("os.") + 1,
        Path(sys.executable),
        None,
    )
    assert not [i for i in hidden if i["label"].startswith("_") and not i["label"].startswith("__")]

    asked = jedi_completions(
        "import os\nos._",
        "module.py",
        2,
        len("os._") + 1,
        Path(sys.executable),
        None,
        prefix="_",
    )
    assert [i for i in asked if i["label"].startswith("_")]


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_jedi_definitions_follow_imports_to_the_definition() -> None:
    """``goto`` lands on the definition; ``infer`` would land on its type."""
    content = "from json import dumps\nvalue = dumps\n"
    defs = jedi_definitions(content, "module.py", 2, len("value = dumps"), Path(sys.executable), None)
    assert defs
    assert defs[0]["name"] == "dumps"
    assert "json" in defs[0]["file_path"]


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_jedi_references_finds_every_usage() -> None:
    content = "def helper():\n    pass\n\nhelper()\nalias = helper\n"
    refs = jedi_references(content, "module.py", 1, 5, Path(sys.executable), None)
    lines = sorted(ref["line"] for ref in refs)
    assert lines == [1, 4, 5]
    assert all(ref["column"] >= 1 for ref in refs)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_jedi_rename_rewrites_definition_and_usages() -> None:
    content = "def helper():\n    pass\n\nhelper()\n"
    result = jedi_rename(content, "module.py", 1, 5, Path(sys.executable), None, new_name="renamed")
    assert result is not None
    assert result["error"] == ""
    assert len(result["files"]) == 1
    new_code = result["files"][0]["content"]
    assert "def renamed()" in new_code
    assert "renamed()" in new_code
    assert "helper" not in new_code


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_jedi_syntax_errors_report_every_failure() -> None:
    """``ast.parse`` stops at the first error and would hide the second."""
    errors = jedi_syntax_errors("def f(:\n  pass\n\nclass ++X:\n  pass\n", "m.py", Path(sys.executable), None)
    assert len(errors) >= 2
    assert all(item["severity"] == "error" for item in errors)
    assert all(item["column"] >= 1 for item in errors)


def test_python_diagnostics_report_syntax_errors() -> None:
    items = python_diagnostics("def f(:\n    pass\n", "m.py", python_executable=Path(sys.executable))
    assert items
    assert items[0]["severity"] == "error"
    assert items[0]["file_path"] == "m.py"
    assert "Syntax" in items[0]["message"] or "syntax" in items[0]["message"]


@pytest.mark.skipif(not pyflakes_available(), reason="pyflakes not installed")
def test_python_diagnostics_report_undefined_names_and_unused_imports() -> None:
    content = "import os\nimport sys\n\ndef f(a):\n    return missing_name + a\n"
    items = python_diagnostics(content, "m.py", python_executable=Path(sys.executable))
    codes = {item["code"] for item in items}
    assert codes & {"undefined_name", "F821"}
    assert codes & {"unused_import", "F401"}

    undefined = next(
        item for item in items if item["code"] in {"undefined_name", "F821"}
    )
    assert undefined["severity"] == "error"
    assert undefined["line"] == 5
    unused = next(
        item for item in items if item["code"] in {"unused_import", "F401"}
    )
    assert unused["severity"] == "warning"

    # Ordered by position so the Problems panel reads top-to-bottom.
    positions = [(item["line"], item["column"]) for item in items]
    assert positions == sorted(positions)


@pytest.mark.skipif(not pyflakes_available(), reason="pyflakes not installed")
def test_python_diagnostics_skip_semantics_while_unparseable() -> None:
    """Half-typed code makes every name look undefined; only syntax is reported."""
    items = python_diagnostics(
        "import os\n\ndef f(:\n    return missing\n",
        "m.py",
        python_executable=Path(sys.executable),
    )
    assert items
    assert {item["code"] for item in items} == {"syntax"}


def test_python_diagnostics_are_silent_on_clean_code() -> None:
    content = "import os\n\n\ndef f(a):\n    return os.path.join(a, 'b')\n"
    assert python_diagnostics(content, "m.py", python_executable=Path(sys.executable)) == []
    assert python_diagnostics("", "m.py", python_executable=Path(sys.executable)) == []


def test_python_diagnostics_warn_when_package_missing_from_env(tmp_path: Path) -> None:
    missing = "zz_rs_not_a_real_package_9f3c"
    path = tmp_path / "lib.py"
    path.write_text(f"import {missing}\nfrom {missing}.sub import Thing\n", encoding="utf-8")
    items = python_diagnostics(
        path.read_text(encoding="utf-8"),
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
    )
    missing_items = [item for item in items if item["code"] == "missing_package"]
    assert len(missing_items) == 1
    assert missing_items[0]["severity"] == "warning"
    assert missing_items[0]["source"] == "python"
    assert missing in missing_items[0]["message"]
    assert missing_items[0]["line"] == 1
    assert not any(item["code"] in {"unused_import", "F401"} for item in items)
    assert not any(item["code"] == "unresolved_import" for item in items)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_python_diagnostics_warn_unknown_name_from_installed_package(tmp_path: Path) -> None:
    path = tmp_path / "lib.py"
    content = (
        "from pathlib import Path, NoSuchPathClass\n"
        "from os import not_a_real_os_attr_zz\n"
        "\n"
        "def f():\n"
        "    return Path, NoSuchPathClass, not_a_real_os_attr_zz\n"
    )
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
    )
    unresolved = [item for item in items if item["code"] == "unresolved_import"]
    messages = [item["message"] for item in unresolved]
    assert any("NoSuchPathClass" in msg and "pathlib" in msg for msg in messages)
    assert any("not_a_real_os_attr_zz" in msg for msg in messages)
    assert all("'Path'" not in msg for msg in messages)
    assert all(item["severity"] == "warning" for item in unresolved)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_python_diagnostics_unknown_name_from_local_module(tmp_path: Path) -> None:
    (tmp_path / "helper.py").write_text("VALUE = 1\n", encoding="utf-8")
    path = tmp_path / "lib.py"
    content = "from helper import VALUE, NOPE\n\ndef f():\n    return VALUE, NOPE\n"
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
    )
    unresolved = [item for item in items if item["code"] == "unresolved_import"]
    assert len(unresolved) == 1
    assert "NOPE" in unresolved[0]["message"]
    assert "VALUE" not in unresolved[0]["message"]


def test_python_diagnostics_accept_local_module_and_stdlib(tmp_path: Path) -> None:
    (tmp_path / "helper.py").write_text("VALUE = 1\n", encoding="utf-8")
    path = tmp_path / "lib.py"
    content = "import os\nimport helper\n\ndef f():\n    return os.getcwd(), helper.VALUE\n"
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
    )
    assert not any(item["code"] == "missing_package" for item in items)


def test_python_diagnostics_skip_optional_import_error(tmp_path: Path) -> None:
    missing = "zz_rs_optional_pkg_9f3c"
    path = tmp_path / "lib.py"
    content = (
        f"try:\n    import {missing}\nexcept ImportError:\n    {missing} = None\n"
    )
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
    )
    assert not any(item["code"] == "missing_package" for item in items)


def test_python_diagnostics_drop_unused_import_when_package_missing(tmp_path: Path) -> None:
    missing = "zz_rs_not_a_real_package_9f3c"
    path = tmp_path / "lib.py"
    path.write_text(f"import {missing}\n", encoding="utf-8")
    items = python_diagnostics(
        path.read_text(encoding="utf-8"),
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
    )
    assert any(item["code"] == "missing_package" for item in items)
    assert not any(item["code"] in {"unused_import", "F401"} for item in items)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_python_diagnostics_member_checks_off_by_default(tmp_path: Path) -> None:
    path = tmp_path / "lib.py"
    content = (
        "from pathlib import Path\n"
        "\n"
        "def f():\n"
        "    p = Path('.')\n"
        "    return p.no_such_attr_zz\n"
    )
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
    )
    assert not any(item["code"] == "unknown_attribute" for item in items)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_python_diagnostics_unknown_attribute(tmp_path: Path) -> None:
    path = tmp_path / "lib.py"
    content = (
        "from pathlib import Path\n"
        "\n"
        "def f():\n"
        "    p = Path('.')\n"
        "    return p.no_such_attr_zz, p.exists()\n"
    )
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
        python_member_diagnostics=True,
    )
    unknown = [item for item in items if item["code"] == "unknown_attribute"]
    assert len(unknown) == 1
    assert "no_such_attr_zz" in unknown[0]["message"]
    assert all("exists" not in item["message"] for item in unknown)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_python_diagnostics_skip_attributes_in_annotations(tmp_path: Path) -> None:
    path = tmp_path / "lib.py"
    content = (
        "import openpyxl as excel\n"
        "\n"
        "def f(sheet: excel.worksheet.worksheet.Worksheet) -> None:\n"
        "    return sheet.title\n"
    )
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
        python_member_diagnostics=True,
    )
    unknown = [item for item in items if item["code"] == "unknown_attribute"]
    assert not any("Worksheet" in item["message"] for item in unknown)
    assert not any("worksheet" in item["message"] for item in unknown)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_python_diagnostics_skip_generic_tuple_cell_attributes(tmp_path: Path) -> None:
    path = tmp_path / "lib.py"
    content = (
        "def f(row):\n"
        "    return [cell.value for cell in row]\n"
    )
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
        python_member_diagnostics=True,
    )
    assert not any(item["code"] == "unknown_attribute" for item in items)


@pytest.mark.skipif(not jedi_available(), reason="jedi not installed")
def test_python_diagnostics_unexpected_call_keyword(tmp_path: Path) -> None:
    path = tmp_path / "lib.py"
    content = (
        "def greet(name, *, loud=False):\n"
        "    return name\n"
        "\n"
        "def f():\n"
        "    greet('a', loud=True, nope_zz=1)\n"
        "    return dict(foo=1)\n"
    )
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
        python_member_diagnostics=True,
    )
    unexpected = [item for item in items if item["code"] == "unexpected_keyword"]
    assert any("nope_zz" in item["message"] for item in unexpected)
    assert all("loud" not in item["message"] for item in unexpected)
    assert all("foo" not in item["message"] for item in unexpected)


def test_python_diagnostics_missing_package_offers_install(tmp_path: Path) -> None:
    missing = "zz_rs_not_a_real_package_9f3c"
    path = tmp_path / "lib.py"
    content = f"import {missing}\n"
    path.write_text(content, encoding="utf-8")
    items = python_diagnostics(
        content,
        str(path),
        python_executable=Path(sys.executable),
        project_root=tmp_path,
    )
    missing_items = [item for item in items if item["code"] == "missing_package"]
    assert len(missing_items) == 1
    hint = missing_items[0].get("quick_fix") or {}
    assert hint.get("kind") == "install_package"
    assert hint.get("package") == missing
