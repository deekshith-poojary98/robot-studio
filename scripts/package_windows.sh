#!/usr/bin/env bash
# Build a double-clickable RobotStudio.exe folder with an embedded backend.
#
# Run on Windows (Git Bash / MSYS) or cross-document for CI. Native Windows
# build requires Flutter Windows desktop + MSVC.
#
# Usage (from repo root, on Windows):
#   ./scripts/package_windows.sh
#
# Output:
#   dist/windows/RobotStudio/
#   dist/windows/RobotStudio-<version>-windows.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend"
DIST="$ROOT/dist/windows"
VENV_PY="${ROBOT_STUDIO_PYTHON:-$BACKEND/.venv/Scripts/python.exe}"
if [[ ! -x "$VENV_PY" && ! -f "$VENV_PY" ]]; then
  VENV_PY="$BACKEND/.venv/bin/python"
fi

echo "==> Robot Studio Windows package"
echo "    root=$ROOT"

if [[ ! -f "$VENV_PY" ]]; then
  echo "Missing backend venv Python — run: make setup-backend" >&2
  exit 1
fi

echo "==> Ensure PyInstaller"
"$VENV_PY" -c "import PyInstaller" 2>/dev/null || \
  "$VENV_PY" -m pip install 'pyinstaller>=6.0'

echo "==> Freeze backend sidecar"
cd "$ROOT"
rm -rf "$ROOT/dist/robot-studio-backend" "$ROOT/build/robot_studio_backend"
"$VENV_PY" -m PyInstaller \
  "$ROOT/packaging/robot_studio_backend.spec" \
  --noconfirm --clean \
  --distpath "$ROOT/dist" \
  --workpath "$ROOT/build/pyinstaller"

SIDECAR_DIR="$ROOT/dist/robot-studio-backend"
SIDECAR_BIN="$SIDECAR_DIR/robot-studio-backend.exe"
if [[ ! -f "$SIDECAR_BIN" ]]; then
  # Non-Windows freeze may produce no .exe — fail clearly.
  if [[ -f "$SIDECAR_DIR/robot-studio-backend" ]]; then
    echo "Built a non-Windows sidecar. Run this script on Windows." >&2
  fi
  echo "PyInstaller did not produce $SIDECAR_BIN" >&2
  exit 1
fi

echo "==> Flutter build windows --release"
cd "$FRONTEND"
flutter pub get
flutter build windows --release

RELEASE_DIR="$FRONTEND/build/windows/x64/runner/Release"
if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "Missing Flutter Release dir: $RELEASE_DIR" >&2
  exit 1
fi

echo "==> Assemble dist bundle"
rm -rf "$DIST"
mkdir -p "$DIST/RobotStudio"
cp -R "$RELEASE_DIR"/. "$DIST/RobotStudio/"
mkdir -p "$DIST/RobotStudio/backend"
cp -R "$SIDECAR_DIR"/. "$DIST/RobotStudio/backend/"

EXE="$DIST/RobotStudio/RobotStudio.exe"
if [[ ! -f "$EXE" ]]; then
  # Older builds may still be named robot_studio.exe
  if [[ -f "$DIST/RobotStudio/robot_studio.exe" ]]; then
    mv "$DIST/RobotStudio/robot_studio.exe" "$EXE"
  else
    echo "Could not find RobotStudio.exe in bundle" >&2
    ls -la "$DIST/RobotStudio" >&2 || true
    exit 1
  fi
fi

VERSION="$("$VENV_PY" -c 'from robot_studio import __version__; print(__version__)')"
ZIP="$DIST/RobotStudio-${VERSION}-windows.zip"
echo "==> Zip $ZIP"
rm -f "$ZIP"
(
  cd "$DIST"
  if command -v zip >/dev/null 2>&1; then
    zip -r "$(basename "$ZIP")" RobotStudio
  else
    powershell.exe -NoProfile -Command \
      "Compress-Archive -Path 'RobotStudio' -DestinationPath '$(basename "$ZIP")' -Force"
  fi
)

echo ""
echo "Packaged:"
echo "  $DIST/RobotStudio/RobotStudio.exe"
echo "  $ZIP"
echo ""
echo "Beta users: unzip and double-click RobotStudio.exe"
