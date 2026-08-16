#!/usr/bin/env bash
# Install a user menu launcher so Robot Studio appears in the app grid.
# Run once from the unzipped RobotStudio folder:
#   ./install-desktop-launcher.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/robot_studio"
if [[ ! -x "$BIN" ]]; then
  echo "Missing executable: $BIN" >&2
  echo "Keep this script next to robot_studio inside the unzipped folder." >&2
  exit 1
fi

APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
mkdir -p "$APPS" "$ICONS"

ICON_SRC=""
for candidate in \
  "$HERE/robot-studio.png" \
  "$HERE/data/flutter_assets/assets/branding/logo-mark.png"
do
  if [[ -f "$candidate" ]]; then
    ICON_SRC="$candidate"
    break
  fi
done
if [[ -n "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$ICONS/robot-studio.png"
fi

DESKTOP="$APPS/robot-studio.desktop"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Robot Studio
Comment=Robot Framework IDE
Exec=$BIN
Path=$HERE
Icon=robot-studio
Terminal=false
Categories=Development;IDE;
StartupWMClass=robot_studio
Keywords=robot;framework;testing;ide;
EOF
chmod +x "$DESKTOP"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" 2>/dev/null || true
fi

echo "Installed launcher: $DESKTOP"
echo "Search for “Robot Studio” in your app menu, or run: $BIN"
