"""Quick-fix hints attached to diagnostics (install a package, insert Library).

Kept pure so unit tests do not need a workspace or Jedi. The Problems panel
shows **Fix** when a diagnostic carries a ``quick_fix`` payload; the client
applies install via Packages and Library inserts in the editor buffer.
"""

from __future__ import annotations

import re
from typing import Any

# Robot library import name → PyPI distribution. Unmapped names are not
# offered an install action (a typo is more likely than a discoverable wheel).
LIBRARY_TO_PYPI: dict[str, str] = {
    "appiumlibrary": "robotframework-appiumlibrary",
    "archivelibrary": "robotframework-archivelibrary",
    "browser": "robotframework-browser",
    "databaselibrary": "robotframework-databaselibrary",
    "excellibrary": "robotframework-excellibrary",
    "fakerlibrary": "robotframework-faker",
    "ftplibrary": "robotframework-ftplibrary",
    "requestslibrary": "robotframework-requests",
    "restinstance": "RESTinstance",
    "seleniumlibrary": "robotframework-seleniumlibrary",
    "sshlibrary": "robotframework-sshlibrary",
}

# ``import name`` → pip name when they differ. Identity is the default.
IMPORT_TO_PYPI: dict[str, str] = {
    "attr": "attrs",
    "bs4": "beautifulsoup4",
    "cv2": "opencv-python",
    "dateutil": "python-dateutil",
    "dotenv": "python-dotenv",
    "git": "GitPython",
    "image": "pillow",
    "pil": "pillow",
    "rest_framework": "djangorestframework",
    "serial": "pyserial",
    "sklearn": "scikit-learn",
    "yaml": "pyyaml",
}

_QUOTED = re.compile(r"'([^']+)'")
_SETTINGS_HEADER = re.compile(r"^\*+\s*settings?\s*\*+", re.IGNORECASE)
_SECTION_HEADER = re.compile(r"^\*+\s+\S+")
_BUILTIN_LIBS = frozenset({"builtin", "reserved"})


def quoted_name(message: str) -> str:
    """First single-quoted token in a diagnostic message, or empty."""
    match = _QUOTED.search(message or "")
    return (match.group(1) if match else "").strip()


def looks_like_import_path(name: str) -> bool:
    text = (name or "").strip().strip("'\"")
    if not text:
        return False
    return (
        "/" in text
        or "\\" in text
        or text.endswith((".py", ".pyi", ".robot", ".resource"))
    )


def pypi_package_for_library(name: str) -> str | None:
    """PyPI dist for a Robot ``Library`` name, or None when we should not install."""
    cleaned = (name or "").strip().strip("'\"")
    if not cleaned or looks_like_import_path(cleaned):
        return None
    return LIBRARY_TO_PYPI.get(cleaned.casefold())


def pypi_package_for_import(name: str) -> str | None:
    """PyPI dist for a Python import name (missing_package diagnostics)."""
    cleaned = (name or "").strip().strip("'\"")
    if not cleaned or looks_like_import_path(cleaned):
        return None
    mapped = IMPORT_TO_PYPI.get(cleaned.casefold())
    if mapped:
        return mapped
    if re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", cleaned):
        return cleaned
    return None


def library_qualifier(keyword: str) -> str | None:
    """``RequestsLibrary.GET On Session`` → ``RequestsLibrary``; None if unqualified."""
    raw = (keyword or "").strip()
    if "." not in raw:
        return None
    head, _, rest = raw.partition(".")
    head = head.strip()
    if not rest or not head:
        return None
    if head.startswith(("$", "@", "&", "%")):
        return None
    if head.casefold() in _BUILTIN_LIBS:
        return None
    if looks_like_import_path(head):
        return None
    return head


def library_already_imported(content: str, library: str) -> bool:
    target = (library or "").strip().casefold()
    if not target:
        return False
    for raw in content.splitlines():
        line = raw.strip()
        if not line.lower().startswith("library "):
            continue
        rest = line.split(None, 1)[1].strip()
        cells = [cell for cell in re.split(r"[ \t]{2,}|\t+", rest) if cell]
        token = (cells[0] if cells else rest.split()[0] if rest.split() else "").strip(
            "'\"",
        )
        if token.casefold() == target:
            return True
    return False


def insert_library_import(content: str, library: str) -> str | None:
    """Return buffer with ``Library    X`` in Settings, or None if already present."""
    name = (library or "").strip().strip("'\"")
    if not name or library_already_imported(content, name):
        return None

    newline = "\r\n" if "\r\n" in content else "\n"
    row = f"Library    {name}"
    if not content.strip():
        return f"*** Settings ***{newline}{row}{newline}"

    lines = content.splitlines(keepends=True)

    settings_at: int | None = None
    section_end = len(lines)
    for index, raw in enumerate(lines):
        stripped = raw.strip()
        if settings_at is None and _SETTINGS_HEADER.match(stripped):
            settings_at = index
            continue
        if settings_at is not None and index > settings_at and _SECTION_HEADER.match(stripped):
            section_end = index
            break

    if settings_at is None:
        block = f"*** Settings ***{newline}{row}{newline}{newline}"
        return block + content

    insert_at = settings_at + 1
    last_library = settings_at
    for index in range(settings_at + 1, section_end):
        stripped = lines[index].strip()
        if stripped.lower().startswith("library "):
            last_library = index
    insert_at = last_library + 1

    prefix = "".join(lines[:insert_at])
    suffix = "".join(lines[insert_at:])
    # Keep a blank line before the next section when we insert at the boundary.
    extra = ""
    if suffix.lstrip().startswith("*") and not prefix.endswith(newline + newline):
        extra = newline
    return f"{prefix}{row}{newline}{extra}{suffix}"


def quick_fix_hint(
    *,
    code: str | None,
    message: str,
    content: str = "",
) -> dict[str, Any] | None:
    """Client payload for Problems **Fix**, or None when nothing can be applied."""
    kind = (code or "").strip()
    if kind == "missing_library":
        name = quoted_name(message)
        package = pypi_package_for_library(name)
        if not package:
            return None
        return {
            "kind": "install_package",
            "title": f"Install {package}",
            "package": package,
        }
    if kind == "missing_package":
        name = quoted_name(message)
        package = pypi_package_for_import(name)
        if not package:
            return None
        return {
            "kind": "install_package",
            "title": f"Install {package}",
            "package": package,
        }
    if kind == "unknown_keyword":
        keyword = quoted_name(message)
        library = library_qualifier(keyword)
        if not library or library_already_imported(content, library):
            return None
        return {
            "kind": "insert_library",
            "title": f"Add Library    {library}",
            "library": library,
        }
    return None
