---
title: Install
description: Get a private beta build, or run from source for development.
---

:::caution[Private beta]
Packaged builds are zip downloads for **macOS**, **Windows**, and **Linux** (x64 and arm64). There is no installer (no `.dmg` / `.msi` / `.deb`).

There is **no published GitHub Release artifact** for Robot Studio yet. Private beta testers use a **supplied zip**, or a zip from the **Package Desktop** GitHub Actions workflow. File bugs on [GitHub Issues](https://github.com/deekshith-poojary98/robot-studio/issues).
:::

## Packaged beta (recommended for testers)

1. Obtain the zip for your OS **and CPU** (supplied by the maintainers, or downloaded from an Actions run — see below).
2. Unzip it somewhere convenient (Applications, Desktop, or a beta folder). On macOS you can drag **Robot Studio.app** into Applications yourself.
3. **Launch the app** — do not start a Python process by hand. Keep the unzipped folder together (Windows / Linux need `backend/` next to the binary).
4. Quitting the app stops the embedded backend sidecar.

| Platform | Artifact | How to open |
|----------|----------|-------------|
| **macOS** | `Robot Studio.app` (inside the zip) | Double-click the app. First launch after unzip is often blocked by Gatekeeper — see [macOS: app blocked after unzip](#macos-app-blocked-after-unzip) below. |
| **Windows** | `RobotStudio/RobotStudio.exe` (inside the zip) | Double-click the executable. If Windows reports missing `MSVCP140.dll` / `VCRUNTIME140.dll`, install the [Visual C++ Redistributable (x64)](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist) once, then retry. |
| **Linux x64** | `Robot-Studio-*-linux-x64.zip` → `RobotStudio/` | Double-click `robot-studio.desktop` (first time: right-click → **Allow Launching**), or run `./robot_studio`. Optional once: `./install-desktop-launcher.sh` to add it to the app menu. Uninstall: `./uninstall.sh` (add `--purge` to also delete `~/.robot-studio`). |
| **Linux arm64** | `Robot-Studio-*-linux-arm64.zip` → `RobotStudio/` | Same as Linux x64. Use this zip on Apple Silicon / ARM VMs (`uname -m` → `aarch64`). An x64 zip shows `Exec format error` on ARM. |

### Where maintainers get zips today

From the repository: **Actions → Package Desktop → Run workflow**. Download each OS zip from that run’s **artifacts**.

Local packaging (must run on that OS — no cross-compile):

```bash
make package-macos      # → dist/macos/Robot Studio.app
make package-windows   # → dist/windows/RobotStudio/  (run on Windows)
make package-linux     # → dist/linux/RobotStudio/    (run on Linux; zip tagged x64 or arm64)
make package           # package for the OS you are on
```

Pushing a `v*` tag is configured to attach platform zips to a GitHub Release. Until a release is published, do **not** expect a download on the Releases page.

### macOS: app blocked after unzip

Beta builds are not notarized. After you unzip and double-click **Robot Studio**, macOS may show **“Robot Studio” Not Opened** and refuse to launch.

1. Open **System Settings → Privacy & Security**.
2. Scroll to the **Security** section. You should see *“Robot Studio” was blocked to protect your Mac.*
3. Click **Open Anyway**, then confirm **Open** on the follow-up prompt.

You only need this once per download. If the blocked message is missing, try opening the app again from Finder first, then return to Privacy & Security.

Same steps are under [Troubleshooting](/troubleshooting/common-issues/#macos-robot-studio-not-opened-after-unzip).

### Linux host packages

On Ubuntu/Debian, creating a project environment also needs the host `venv` package once: `sudo apt install python3-venv` (or `python3.XX-venv` if the error names a version). Source Control needs host Git: `sudo apt install git`. See [Troubleshooting](/troubleshooting/common-issues/).

App data lives under `~/.robot-studio`.

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

See [RELEASE_NOTES.md](https://github.com/deekshith-poojary98/robot-studio/blob/main/RELEASE_NOTES.md) in the repository.

## Next step

→ [Create or open your first project](/getting-started/first-project/)
