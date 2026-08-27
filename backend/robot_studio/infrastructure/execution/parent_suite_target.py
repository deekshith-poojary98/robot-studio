"""Keep parent ``__init__.robot`` Suite Setup when running one file or test.

Robot only executes initialization files for suites *above* the path you pass
on the command line. ``robot tests/posts/posts_api.robot`` skips
``tests/__init__.robot``, so HTTP sessions (and similar) created there never
exist. Starting Robot at that parent directory and filtering with ``--suite``
still runs the setup, then only the selected child.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ParentSuiteTarget:
    """Path passed to ``robot`` plus optional ``--suite`` filter tokens."""

    data_source: Path
    filter_args: tuple[str, ...] = ()


def robot_suite_name_from_path(path: Path) -> str:
    """Match :meth:`robot.model.TestSuite.name_from_source` for ``.robot`` / dirs."""
    raw = path.stem if path.suffix.lower() == ".robot" else path.name
    if "__" in raw:
        raw = raw.split("__", 1)[1] or raw
    raw = raw.replace("_", " ").strip()
    return raw.title() if raw.islower() else raw


def highest_init_directory(target: Path, project_root: Path) -> Path | None:
    """Nearest-to-project directory that contains ``__init__.robot``."""
    try:
        root = project_root.expanduser().resolve()
        current = target.expanduser().resolve()
    except OSError:
        return None
    if current.is_file():
        current = current.parent
    found: Path | None = None
    while True:
        try:
            current.relative_to(root)
        except ValueError:
            break
        if (current / "__init__.robot").is_file():
            found = current
        if current == root:
            break
        parent = current.parent
        if parent == current:
            break
        current = parent
    return found


def expand_parent_suite_target(target: Path, project_root: Path) -> ParentSuiteTarget:
    """Rewrite a file/folder run so ancestor Suite Setup still executes."""
    try:
        resolved = target.expanduser().resolve()
        root = project_root.expanduser().resolve()
        resolved.relative_to(root)
    except (OSError, ValueError):
        return ParentSuiteTarget(data_source=target)

    init_dir = highest_init_directory(resolved, root)
    if init_dir is None:
        return ParentSuiteTarget(data_source=resolved)

    if resolved == init_dir:
        return ParentSuiteTarget(data_source=init_dir)

    try:
        relative = resolved.relative_to(init_dir)
    except ValueError:
        return ParentSuiteTarget(data_source=resolved)

    names: list[str] = [robot_suite_name_from_path(init_dir)]
    parts = relative.parts
    for index, part in enumerate(parts):
        is_last = index == len(parts) - 1
        piece = Path(part)
        if is_last and resolved.is_file():
            names.append(robot_suite_name_from_path(resolved))
        else:
            names.append(robot_suite_name_from_path(piece))
    selector = ".".join(name for name in names if name)
    if not selector:
        return ParentSuiteTarget(data_source=init_dir)
    return ParentSuiteTarget(
        data_source=init_dir,
        filter_args=("--suite", selector),
    )
