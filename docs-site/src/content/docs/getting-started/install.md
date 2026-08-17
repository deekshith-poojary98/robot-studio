---
title: Install
description: Download a private beta build from GitHub Releases, or run from source for development.
---

:::caution[Private beta]
Packaged builds are zip downloads for **macOS**, **Windows**, and **Linux** (x64 and arm64). There is no installer (no `.dmg` / `.msi` / `.deb`).

Download the latest zip from [GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases). File bugs and feature requests on that same repository.
:::

## Packaged beta (recommended for testers)

1. Open [GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases) and download the zip for your OS **and CPU**.
2. Unzip it somewhere convenient (Applications, Desktop, or a beta folder). On macOS you can drag **Robot Studio.app** into Applications yourself.
3. **Launch the app** — do not start a Python process by hand. Keep the unzipped folder together (Windows / Linux need `backend/` next to the binary).
4. Quitting the app stops the embedded backend sidecar.

| Platform | Artifact | How to open |
|----------|----------|-------------|
| **macOS** | `Robot Studio.app` (inside the zip) | Double-click the app |
| **Windows** | `RobotStudio/RobotStudio.exe` (inside the zip) | Double-click the executable. If Windows reports missing `MSVCP140.dll` / `VCRUNTIME140.dll`, install the [Visual C++ Redistributable (x64)](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist) once, then retry. |
| **Linux x64** | `Robot-Studio-*-linux-x64.zip` → `RobotStudio/` | Double-click `robot-studio.desktop` (first time: right-click → **Allow Launching**), or run `./robot_studio`. Optional once: `./install-desktop-launcher.sh` to add it to the app menu. Uninstall: `./uninstall.sh` (add `--purge` to also delete `~/.robot-studio`). |
| **Linux arm64** | `Robot-Studio-*-linux-arm64.zip` → `RobotStudio/` | Same as Linux x64. Use this zip on Apple Silicon / ARM VMs (`uname -m` → `aarch64`). An x64 zip shows `Exec format error` on ARM. |

On Ubuntu/Debian, creating a project environment also needs the host `venv` package once: `sudo apt install python3-venv` (or `python3.XX-venv` if the error names a version). See [Troubleshooting](/troubleshooting/common-issues/).

App data lives under `~/.robot-studio`.

Maintainers building packages from this repository:

```bash
make package-macos      # → dist/macos/Robot Studio.app
make package-windows   # → dist/windows/RobotStudio/  (run on Windows)
make package-linux     # → dist/linux/RobotStudio/    (run on Linux; zip tagged x64 or arm64)
make package           # package for the OS you are on
```

**Cross-OS builds:** do not use a VM. Push to GitHub, then **Actions → Package Desktop → Run workflow**. Download each OS zip from the run’s artifacts (or push a `v*` tag to attach all platform zips to a Release).

## Run from source (developers)

Supported desktop targets when developing from the repository: **macOS**, **Windows**, and **Linux** (Flutter desktop). This path is for contributors — not the private beta hand-off.

### Prerequisites

- **Flutter** 3.x with desktop enabled (`macos`, `linux`, or `windows`)
- **Python** 3.11+
- **Git** (for Source Control features)
- Optional: [uv](https://github.com/astral-sh/uv) for faster backend installs

### One-time setup

From the repository root:

```bash
make setup             # backend virtualenv + flutter pub get
```

### Everyday loop (two terminals)

1. Start the backend:

```bash
make backend           # API on http://127.0.0.1:8765
```

2. Start the UI:

```bash
make run               # flutter run on this OS
```

Check health anytime:

```bash
make health
```

The UI connects to `http://127.0.0.1:8765`. When that backend is already healthy, the app will **not** spawn a sidecar.

Override device or port if needed: `make run DEVICE=linux` · `make backend PORT=8766`.

## What’s in this build

See [RELEASE_NOTES.md](https://github.com/deekshith-poojary98/robot-studio/blob/main/RELEASE_NOTES.md) in the repository (same text as the GitHub Release).

## Next step

→ [Create or open your first project](/getting-started/first-project/)
