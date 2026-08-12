---
title: Install
description: Download a private beta build from GitHub Releases, or run from source for development.
---

:::caution[Private beta]
Packaged builds are **macOS** and **Windows** only. There is no installer (no `.dmg` / `.msi`) and **no packaged Linux build**.

Download the latest zip from [GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases). File bugs and feature requests on that same repository.
:::

## Packaged beta (recommended for testers)

1. Open [GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases) and download the zip for your OS.
2. Unzip it somewhere convenient (Applications, Desktop, or a beta folder). On macOS you can drag **Robot Studio.app** into Applications yourself.
3. **Double-click to launch** — do not start a Python process by hand.
4. Quitting the app stops the embedded backend sidecar.

| Platform | Artifact | How to open |
|----------|----------|-------------|
| **macOS** | `Robot Studio.app` (inside the zip) | Double-click the app |
| **Windows** | `RobotStudio/RobotStudio.exe` (inside the zip) | Double-click the executable |
| **Linux** | *No packaged beta* | Not a packaged target — see source below |

App data lives under `~/.robot-studio`.

Maintainers building packages from this repository:

```bash
make package-macos      # → dist/macos/Robot Studio.app
make package-windows   # → dist/windows/RobotStudio/  (run on Windows)
make package           # package for the OS you are on
```

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
