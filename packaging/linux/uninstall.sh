#!/usr/bin/env bash
# Remove the user menu launcher installed by install-desktop-launcher.sh.
# Run from the unzipped RobotStudio folder:
#   ./uninstall.sh
#   ./uninstall.sh --purge   # also delete ~/.robot-studio (settings, logs, pid)
#
# This does not delete the unzipped app folder (this script lives inside it).
# After it finishes, you can remove the folder yourself.
set -euo pipefail

PURGE=0
for arg in "$@"; do
  case "$arg" in
    --purge|-p) PURGE=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./uninstall.sh [--purge]

Removes the Robot Studio app-menu launcher and icon.

  --purge    Also delete ~/.robot-studio (settings, logs, backend pid file)
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done

APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
DESKTOP="$APPS/robot-studio.desktop"
ICON="$ICONS/robot-studio.png"
DATA="${ROBOT_STUDIO_HOME:-$HOME/.robot-studio}"

removed=0

if [[ -e "$DESKTOP" ]]; then
  rm -f "$DESKTOP"
  echo "Removed launcher: $DESKTOP"
  removed=1
fi
if [[ -e "$ICON" ]]; then
  rm -f "$ICON"
  echo "Removed icon: $ICON"
  removed=1
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" 2>/dev/null || true
fi

if [[ "$PURGE" -eq 1 ]]; then
  if [[ -e "$DATA" ]]; then
    rm -rf "$DATA"
    echo "Removed app data: $DATA"
    removed=1
  else
    echo "No app data at $DATA"
  fi
fi

if [[ "$removed" -eq 0 ]]; then
  echo "Nothing to uninstall (no launcher, icon, or --purge data found)."
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "The unzipped app is still at: $HERE"
echo "Delete that folder when you are done. Use --purge to also remove $DATA"
