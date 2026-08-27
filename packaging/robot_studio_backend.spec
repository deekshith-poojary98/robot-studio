# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for the Robot Studio backend sidecar.

Build (from repo root, with packaging venv or backend/.venv + pyinstaller):

  pyinstaller packaging/robot_studio_backend.spec --noconfirm --clean

Output: dist/robot-studio-backend/robot-studio-backend[.exe]
"""

from __future__ import annotations

import sys
from pathlib import Path

from PyInstaller.utils.hooks import collect_all, collect_submodules

ROOT = Path(SPECPATH).resolve().parent
BACKEND = ROOT / "backend"

block_cipher = None

datas: list = []
binaries: list = []
hiddenimports: list[str] = [
    "uvicorn.logging",
    "uvicorn.loops",
    "uvicorn.loops.auto",
    "uvicorn.protocols",
    "uvicorn.protocols.http",
    "uvicorn.protocols.http.auto",
    "uvicorn.protocols.websockets",
    "uvicorn.protocols.websockets.auto",
    "uvicorn.lifespan",
    "uvicorn.lifespan.on",
    "robot_studio",
    "robot_studio.main",
    "multipart",
    "email_validator",
]

# jedi/parso back Python intelligence and carry non-importable payloads that a
# bare module scan misses: parso's grammar*.txt and jedi's typeshed .pyi stubs.
# Jedi is used with InterpreterEnvironment (in-process) precisely so it never
# needs its own .py sources on disk, which the archive does not provide.
for pkg in (
    "uvicorn",
    "fastapi",
    "starlette",
    "pydantic",
    "anyio",
    "robot",
    "jedi",
    "parso",
    "pyflakes",
):
    try:
        pkg_datas, pkg_binaries, pkg_hidden = collect_all(pkg)
        datas += pkg_datas
        binaries += pkg_binaries
        hiddenimports += pkg_hidden
    except Exception:  # noqa: BLE001 — optional packages may be absent
        hiddenimports += collect_submodules(pkg)

hiddenimports = sorted(set(hiddenimports))

# Scripts that must remain real .py files on disk for the project venv to exec
# (project venv cannot import robot_studio from the frozen sidecar).
datas += [
    (
        str(
            BACKEND
            / "robot_studio"
            / "infrastructure"
            / "execution"
            / "studio_progress_listener.py"
        ),
        "robot_studio/infrastructure/execution",
    ),
    (
        str(
            BACKEND
            / "robot_studio"
            / "infrastructure"
            / "language"
            / "robot_parsing_worker.py"
        ),
        "robot_studio/infrastructure/language",
    ),
]

a = Analysis(
    [str(BACKEND / "robot_studio" / "__main__.py")],
    pathex=[str(BACKEND)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "pytest"],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="robot-studio-backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False if sys.platform == "win32" else True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="robot-studio-backend",
)
