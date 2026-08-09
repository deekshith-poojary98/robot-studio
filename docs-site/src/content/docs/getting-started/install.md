---
title: Install
description: Install the packaged Robot Studio app or run from source for development.
---

You can use Robot Studio as a **packaged desktop app** (recommended for day-to-day use) or run it from source while contributing.

## Packaged app (recommended)

Beta builds ship as a normal desktop app. **Double-click to launch** — do not start a Python process by hand.

| Platform | What you get | How to open |
|----------|--------------|-------------|
| **macOS** | `Robot Studio.app` | Double-click the app |
| **Windows** | `RobotStudio.exe` | Double-click the executable |

The package embeds a frozen backend sidecar and starts it on launch. Quitting the app stops the sidecar. App data lives under `~/.robot-studio`.

If you are building packages from this repository:

```bash
make package-macos      # → dist/macos/Robot Studio.app
make package-windows   # → dist/windows/RobotStudio/  (run on Windows)
make package           # package for the OS you are on
```

## Run from source (developers)

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
