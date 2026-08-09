---
title: Install
description: Launch a private beta build, or run from source for development.
---

:::caution[Private beta]
Robot Studio beta is **not** distributed via a public download page.

You need a **beta build provided by the Robot Studio team** (for example a shared `Robot Studio.app` or `RobotStudio.exe`). This guide does not invent a download URL.

**Linux:** there is **no packaged Linux build**. Do not treat Linux as a packaged beta target — use [run from source](#run-from-source-developers) only if you are developing against the repo.
:::

## Packaged beta (recommended for testers)

Once you have the artifact from the team:

1. Place it somewhere convenient (Applications, Desktop, or a shared beta folder).
2. **Double-click to launch** — do not start a Python process by hand.
3. Quitting the app stops the embedded backend sidecar.

| Platform | Artifact | How to open |
|----------|----------|-------------|
| **macOS** | `Robot Studio.app` | Double-click the app |
| **Windows** | `RobotStudio.exe` | Double-click the executable |
| **Linux** | *No packaged beta* | Not a packaged target — see source below |

App data lives under `~/.robot-studio`.

If the team builds packages from this repository (maintainers):

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

## Next step

→ [Create or open your first project](/getting-started/first-project/)
