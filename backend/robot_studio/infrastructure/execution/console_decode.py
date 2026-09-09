"""Decode Robot Framework console bytes for Live Output / Now Running."""

from __future__ import annotations

import locale


def decode_robot_console_line(line: bytes) -> str:
    """Decode one Robot console line.

    Prefer UTF-8. On Windows, Robot may still emit the active code page
    (e.g. cp1252 ``0xB7`` for ``·``); treating that as UTF-8 with
    ``errors='replace'`` turns it into ``�``. Fall back to the preferred
    locale encoding before replacing.
    """
    raw = line.rstrip(b"\r\n")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        pass
    for encoding in (
        "utf-8-sig",
        locale.getpreferredencoding(False) or "cp1252",
        "cp1252",
        "latin-1",
    ):
        try:
            return raw.decode(encoding)
        except (LookupError, UnicodeDecodeError):
            continue
    return raw.decode("utf-8", errors="replace")
