#!/usr/bin/env bash
# Build a double-clickable Robot Studio.app with an embedded backend sidecar.
#
# Usage (from repo root):
#   ./scripts/package_macos.sh
#
# Output:
#   dist/macos/Robot Studio.app
#   dist/macos/Robot-Studio-<version>.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend"
DIST="$ROOT/dist/macos"
VENV_PY="${ROBOT_STUDIO_PYTHON:-$BACKEND/.venv/bin/python}"
APP_NAME="Robot Studio.app"

echo "==> Robot Studio macOS package"
echo "    root=$ROOT"

if [[ ! -x "$VENV_PY" ]]; then
  echo "Missing $VENV_PY — run: make setup-backend" >&2
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
SIDECAR_BIN="$SIDECAR_DIR/robot-studio-backend"
if [[ ! -x "$SIDECAR_BIN" ]]; then
  echo "PyInstaller did not produce $SIDECAR_BIN" >&2
  exit 1
fi

echo "==> Flutter build macos --release"
cd "$FRONTEND"
flutter pub get
flutter build macos --release

# Flutter places the .app under build/macos/Build/Products/Release/
APP_SRC="$(find "$FRONTEND/build/macos" -name "$APP_NAME" -type d | head -n 1)"
if [[ -z "$APP_SRC" ]]; then
  # Fallback if PRODUCT_NAME change hasn't taken effect yet
  APP_SRC="$(find "$FRONTEND/build/macos" -name '*.app' -type d | head -n 1)"
fi
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "Could not find built .app under frontend/build/macos" >&2
  exit 1
fi
echo "    built: $APP_SRC"

echo "==> Assemble dist bundle"
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$APP_SRC" "$DIST/$APP_NAME"

APP="$DIST/$APP_NAME"
BACKEND_DST="$APP/Contents/Resources/backend"
rm -rf "$BACKEND_DST"
mkdir -p "$APP/Contents/Resources"
cp -R "$SIDECAR_DIR" "$BACKEND_DST"
chmod +x "$BACKEND_DST/robot-studio-backend"

# Ad-hoc sign so Gatekeeper is less angry on local/beta machines.
if command -v codesign >/dev/null 2>&1; then
  echo "==> Ad-hoc codesign"
  codesign --force --deep --sign - "$APP" || true
fi

VERSION="$("$VENV_PY" -c 'from robot_studio import __version__; print(__version__)')"
ZIP="$DIST/Robot-Studio-${VERSION}-macos.zip"
echo "==> Zip $ZIP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo ""
echo "Packaged:"
echo "  $APP"
echo "  $ZIP"
echo ""
echo "Beta users: unzip (if needed) and double-click Robot Studio.app"
echo "Dev tip: keep using make backend + make run while iterating."
