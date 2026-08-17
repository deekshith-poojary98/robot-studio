#!/usr/bin/env bash
# Build a runnable Linux folder with an embedded backend sidecar.
#
# Usage (from repo root, on Linux):
#   ./scripts/package_linux.sh
#
# Output (arch-tagged; x64 and arm64 are separate CI artifacts):
#   dist/linux/RobotStudio/          (robot_studio + lib/ + data/ + backend/ + launcher)
#   dist/linux/Robot-Studio-<version>-linux-<x64|arm64>.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend"
DIST="$ROOT/dist/linux"
VENV_PY="${ROBOT_STUDIO_PYTHON:-$BACKEND/.venv/bin/python}"
BUNDLE_NAME="RobotStudio"
BINARY_NAME="robot_studio"
LINUX_PACKAGING="$ROOT/packaging/linux"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64|amd64) ARCH_TAG="x64" ;;
  aarch64|arm64) ARCH_TAG="arm64" ;;
  *) ARCH_TAG="$HOST_ARCH" ;;
esac

echo "==> Robot Studio Linux package ($ARCH_TAG)"
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

echo "==> Flutter build linux --release"
cd "$FRONTEND"
flutter pub get
flutter build linux --release

# Prefer the bundle that matches this machine (CI builds one arch per job).
BUNDLE_SRC=""
PREFERRED="$FRONTEND/build/linux/${ARCH_TAG}/release/bundle"
OTHER="$FRONTEND/build/linux/x64/release/bundle"
if [[ "$ARCH_TAG" == "x64" ]]; then
  OTHER="$FRONTEND/build/linux/arm64/release/bundle"
fi
for candidate in "$PREFERRED" "$OTHER"; do
  if [[ -d "$candidate" && -f "$candidate/$BINARY_NAME" ]]; then
    BUNDLE_SRC="$candidate"
    break
  fi
done
if [[ -z "$BUNDLE_SRC" ]]; then
  BUNDLE_SRC="$(find "$FRONTEND/build/linux" -type d -name bundle 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$BUNDLE_SRC" || ! -d "$BUNDLE_SRC" ]]; then
  echo "Could not find Flutter Linux release bundle under frontend/build/linux" >&2
  exit 1
fi
echo "    built: $BUNDLE_SRC"

echo "==> Assemble dist bundle"
rm -rf "$DIST"
mkdir -p "$DIST/$BUNDLE_NAME"
cp -a "$BUNDLE_SRC"/. "$DIST/$BUNDLE_NAME/"
mkdir -p "$DIST/$BUNDLE_NAME/backend"
cp -a "$SIDECAR_DIR"/. "$DIST/$BUNDLE_NAME/backend/"
chmod +x "$DIST/$BUNDLE_NAME/$BINARY_NAME"
chmod +x "$DIST/$BUNDLE_NAME/backend/robot-studio-backend"

# Double-click / app-menu helpers (no Flutter/Python required for end users).
cp "$LINUX_PACKAGING/robot-studio.desktop" "$DIST/$BUNDLE_NAME/"
cp "$LINUX_PACKAGING/install-desktop-launcher.sh" "$DIST/$BUNDLE_NAME/"
cp "$LINUX_PACKAGING/uninstall.sh" "$DIST/$BUNDLE_NAME/"
chmod +x "$DIST/$BUNDLE_NAME/install-desktop-launcher.sh"
chmod +x "$DIST/$BUNDLE_NAME/uninstall.sh"
ICON_SRC="$FRONTEND/assets/branding/logo-mark.png"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$DIST/$BUNDLE_NAME/robot-studio.png"
fi

VERSION="$("$VENV_PY" -c 'from robot_studio import __version__; print(__version__)')"
ZIP="$DIST/Robot-Studio-${VERSION}-linux-${ARCH_TAG}.zip"
echo "==> Zip $ZIP"
rm -f "$ZIP"
(
  cd "$DIST"
  # zip(1) stores Unix modes — keep +x on robot_studio / launcher scripts.
  if command -v zip >/dev/null 2>&1; then
    zip -r "$(basename "$ZIP")" "$BUNDLE_NAME"
  else
    tar -czf "${ZIP%.zip}.tar.gz" "$BUNDLE_NAME"
    echo "zip not found — wrote ${ZIP%.zip}.tar.gz instead" >&2
    ZIP="${ZIP%.zip}.tar.gz"
  fi
)

echo ""
echo "Packaged:"
echo "  $DIST/$BUNDLE_NAME/$BINARY_NAME"
echo "  $ZIP"
echo ""
echo "Beta users ($ARCH_TAG): unzip and either"
echo "  ./RobotStudio/robot_studio"
echo "  or double-click RobotStudio/robot-studio.desktop (Allow Launching)"
echo "  or run ./RobotStudio/install-desktop-launcher.sh once for the app menu"
echo "Uninstall: ./RobotStudio/uninstall.sh   (add --purge to delete ~/.robot-studio)"
echo "Keep the whole RobotStudio folder together (lib/, data/, backend/)."
