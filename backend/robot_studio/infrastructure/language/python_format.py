"""Format Python source with the formatter the project already uses.

Robot Studio does not bundle a Python formatter. Formatting is opinionated and
config-driven (``pyproject.toml``, line length, magic trailing comma), so the
only formatter that produces a diff the project's own CI agrees with is the one
installed in its environment. We probe the active interpreter for ruff, then
black, and leave the buffer untouched when neither is present.
"""

from __future__ import annotations

import logging
import subprocess
from pathlib import Path

from robot_studio.infrastructure.process_utils import windows_no_window_kwargs

logger = logging.getLogger(__name__)

_TIMEOUT_SECONDS = 20

# ``-`` reads stdin; ``--stdin-filename`` lets both tools pick up the file's
# own pyproject config instead of defaults.
_FORMATTERS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("ruff", ("-m", "ruff", "format", "--stdin-filename", "{path}", "-")),
    ("black", ("-m", "black", "--quiet", "--stdin-filename", "{path}", "-")),
)


def format_python_source(
    content: str,
    file_path: str,
    python_executable: Path,
) -> str | None:
    """Formatted source, or ``None`` when no formatter is available."""
    if not content.strip():
        return None

    target = file_path or "buffer.py"
    for name, argv in _FORMATTERS:
        args = [str(python_executable), *(arg.format(path=target) for arg in argv)]
        try:
            result = subprocess.run(
                args,
                input=content,
                capture_output=True,
                text=True,
                timeout=_TIMEOUT_SECONDS,
                check=False,
                **windows_no_window_kwargs(),
            )
        except (OSError, subprocess.TimeoutExpired):
            logger.debug("%s formatter unavailable for %s", name, target, exc_info=True)
            continue

        if result.returncode != 0:
            # Not installed vs. refused to format (syntax error) both land here;
            # either way the next candidate — or the caller's fallback — decides.
            logger.debug(
                "%s exited %s for %s: %s",
                name,
                result.returncode,
                target,
                (result.stderr or "").strip()[:200],
            )
            continue
        if result.stdout:
            return result.stdout
    return None
