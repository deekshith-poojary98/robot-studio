<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/deekshith-poojary98/robot-studio/main/docs/branding/logo-wordmark-readme.png">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/deekshith-poojary98/robot-studio/main/docs/branding/logo-wordmark-readme-light.png">
  <img alt="Robot Studio Logo" src="https://raw.githubusercontent.com/deekshith-poojary98/robot-studio/main/docs/branding/logo-wordmark-readme-light.png" width="200">
</picture>

<p>A desktop IDE for <a href="https://robotframework.org/">Robot Framework</a> — open a project, activate an environment, write tests, run them, and read reports in one app.</p>

<p>
  <a href="./backend/pyproject.toml"><img alt="Python" src="https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python&logoColor=white"></a>
  <a href="./frontend/pubspec.yaml"><img alt="Dart" src="https://img.shields.io/badge/Dart-%5E3.10.1-0175C2?logo=dart&logoColor=white"></a>
  <a href="https://docs.flutter.dev/release/archive"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.38%2B%20(stable)-02569B?logo=flutter&logoColor=white"></a>
  <a href="https://robotframework.org/"><img alt="Robot Framework" src="https://img.shields.io/badge/Robot%20Framework-7%2B-000000?logo=robotframework&logoColor=white"></a>
  <img alt="Platform" src="https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey">
  <a href="https://github.com/deekshith-poojary98/robot-studio/actions/workflows/unit-tests.yml"><img alt="Unit tests" src="https://github.com/deekshith-poojary98/robot-studio/actions/workflows/unit-tests.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/deekshith-poojary98/robot-studio/actions/workflows/package-desktop.yml"><img alt="Build" src="https://github.com/deekshith-poojary98/robot-studio/actions/workflows/package-desktop.yml/badge.svg"></a>
</p>

</div>

**Robot Studio** pairs a Flutter desktop UI with a local Python FastAPI backend. It is built for RF SDETs and automation engineers who want project + environment + editor + runner + reports without assembling a generic IDE from plugins.

| | |
|--|--|
| **User guide** | https://deekshith-poojary98.github.io/robot-studio/ (source: [docs-site/](./docs-site/), preview with `make docs-dev`) |
| **Bugs / feedback** | [GitHub Issues](https://github.com/deekshith-poojary98/robot-studio/issues) |
| **Architecture** | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| **Release notes** | [RELEASE_NOTES.md](./RELEASE_NOTES.md) |

---

## What you can do

| Area | In the app |
|------|------------|
| **Projects** | New / Open / Recent; open any Robot folder (`.robotstudio/` in place); new projects get `tests/` / `resources/` / `variables/` |
| **Environments & packages** | Create / import / activate a venv; install libraries from PyPI |
| **Editor** | Multi-tab Robot + Python editing, completions, diagnostics, go to definition, outline |
| **Run** | Toolbar **Run** / **Project** / **Stop**, Tests tree, run configurations (tags, variables), live logs, Failed Tests with Jump to Source |
| **Reports & Insights** | Run history, HTML report/log, triage from Insights |
| **Doctor** | Structural project health (circular imports, duplicates, unused assets) |
| **Search / Libraries / Git / Terminal / Settings** | Find in Files, library docs, project-scoped Git, bottom terminal, Settings |

Beta: expect bugs. Plugins exist in the codebase but are **hidden from the activity bar** for this beta. No AI assistant, debugger, or impact-analysis product UI in this build.

---

## Beta — how to get a build

Download the zip for your OS from **[GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases)** (assets on the latest `v*` beta tag).

| Platform | What to open |
|----------|----------------|
| macOS | `Robot Studio.app` |
| Windows | `RobotStudio/RobotStudio.exe` |
| Linux | `RobotStudio/robot_studio` (or `robot-studio.desktop`) |

No installer (no `.dmg` / `.msi` / `.deb`). The app embeds the backend sidecar — double-click to launch; quit to stop. App data: `~/.robot-studio`.

Pushing a `v*` tag runs **Actions → Package Desktop** and attaches the platform zips to that Release. Local packaging (must run on that OS):

```bash
make package-macos    # → dist/macos/Robot Studio.app
make package-windows  # → dist/windows/RobotStudio/
make package-linux    # → dist/linux/RobotStudio/
make package          # this OS
```

Full tester notes: [RELEASE_NOTES.md](./RELEASE_NOTES.md) · Install guide: [docs-site install](https://deekshith-poojary98.github.io/robot-studio/getting-started/install/).

---

## Developer setup

### Prerequisites

- **Flutter** 3.38+ (stable) with desktop enabled · Dart `^3.10.1`
- **Python** 3.11+ (packaging CI uses 3.12)
- **Git** (Source Control)
- Optional: [uv](https://github.com/astral-sh/uv)

### Everyday loop

```bash
make setup             # once: backend/.venv + flutter pub get
make backend           # terminal 1 — API on :8765
make run               # terminal 2 — flutter run (macos|linux|windows)
make health            # curl /api/v1/health
make test              # pytest + flutter test
```

When `http://127.0.0.1:8765` is already healthy, the UI does **not** spawn a sidecar.

Override: `make run DEVICE=linux` · `make backend PORT=8766`.

Frontend notes: [frontend/README.md](./frontend/README.md) · Integration tests: [frontend/integration_test/README.md](./frontend/integration_test/README.md).

### Configuration

Backend settings use the `ROBOT_STUDIO_` prefix (`backend/robot_studio/core/config.py`). Day-to-day prefs live in **Settings** (`~/.robot-studio/settings.json`). See the [settings reference](https://deekshith-poojary98.github.io/robot-studio/reference/settings/).

---

## Project layout

```
robot-studio/
├── ARCHITECTURE.md
├── Makefile
├── docs-site/                 # User guide (Astro Starlight → GitHub Pages)
├── backend/robot_studio/      # FastAPI · application · domain · infrastructure
└── frontend/lib/              # Flutter shell, editor, gateway
```

API surface, modules, and transport details: [ARCHITECTURE.md](./ARCHITECTURE.md).

---

## Status

Core IDE loop (open project → environment → edit → run → reports → Doctor) is in place. The product is in **beta** usability hardening. Desktop packaging is zip-only via GitHub Releases (`v*` tag → Actions **Package Desktop**).

Milestone detail and design notes: [ARCHITECTURE.md](./ARCHITECTURE.md).

---

## License

TBD
