<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/deekshith-poojary98/robot-studio/main/docs/branding/logo-wordmark-readme.png">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/deekshith-poojary98/robot-studio/main/docs/branding/logo-wordmark-readme-light.png">
  <img alt="Robot Studio Logo" src="https://raw.githubusercontent.com/deekshith-poojary98/robot-studio/main/docs/branding/logo-wordmark-readme-light.png" width="200">
</picture>

<p>A cross-platform desktop IDE for <a href="https://robotframework.org/">Robot Framework</a> development.</p>

</div>

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/deekshith-poojary98/robot-studio)

Robot Studio pairs a **Flutter desktop** UI with a local **Python FastAPI** backend. Workspaces, projects, environments, packages, indexing, language intelligence, test execution, reports, Git, and plugins are coordinated through clean-architecture services, an in-process event bus, and a transport gateway (REST + WebSocket today).

```
┌─────────────────────────────────────────────────────────┐
│  Flutter Desktop                                        │
│  Shell · Explorer · Editor · Git · Reports · Console    │
└──────────────────────────┬──────────────────────────────┘
                           │  REST + WebSocket (localhost)
┌──────────────────────────▼──────────────────────────────┐
│  Python FastAPI · SQLite · Index Store · Plugin Host    │
│  Runner · PipInstaller · Language Service · Git CLI     │
└─────────────────────────────────────────────────────────┘
```

For the full design (modules, Event Bus, Plugin Host, Indexing, Language Service, transport roadmap), see [ARCHITECTURE.md](./ARCHITECTURE.md).

Frontend-specific docs: [frontend/README.md](./frontend/README.md) · Integration tests: [frontend/integration_test/README.md](./frontend/integration_test/README.md)

---

## Features

| Area | What you get |
|------|----------------|
| **Projects** | Primary entry: New / Open / Recent Projects; open any Robot Framework folder (`.robotstudio/` in-place); new projects get empty `tests/` / `resources/` / `variables/` folders plus a seeded `.gitignore` (ignores `.robotstudio/` and common Python noise) — no template types |
| **Workspaces** | Advanced multi-project containers (Open / New / Recent); still the domain container behind the scenes |
| **Environments** | Create / import / clone / activate; non-blocking prompt on open; Studio venvs live under `.robotstudio/environments/` (legacy root `Environments/` still discovered); also detects `.venv` / `venv` / `env` |
| **Packages** | List installed packages, search PyPI, install / update / uninstall |
| **Editor** | Multi-tab Robot editor, find/replace, live diagnostics (venv `Library` imports via active env); document outline under Explorer |
| **Language intelligence** | Completions split RF DSL vs BuiltIn; hover; F12 / Ctrl+Click Go to Definition (index + Analysis Engine, multi-definition picker); references; document symbols |
| **Problems** | Bottom Problems panel synced while editing; Analysis Engine missing imports share Doctor `missing_import` identity; jump to line/column; status-bar ERRORS/WARNINGS shortcut |
| **Command palette** | ⌘⇧P / Ctrl+Shift+P (also ⌘P / Ctrl+P, ⌘K / Ctrl+K) for commands, recent files, project files, and symbols |
| **Keyboard shortcuts** | VS Code–style chrome + editor chords (save, tabs, sidebar, terminal, find/replace, comment, move/copy/delete line, format, Problems) — see `frontend/README.md` |
| **Indexing** | Background on open (incremental); mid-rebuild `INDEX_PROGRESS` / `ANALYSIS_PROGRESS` on the live workspace stream (status bar + soft overlay); full rebuild on demand; excludes `.venv` / `node_modules` / `.git` |
| **Find in Files** | Left **Search** rail text search (`⌘⇧F` / Ctrl+Shift+F); editor stays mounted; matches decorated with enclosing test/keyword/variable when the index knows; extensions via `ROBOT_STUDIO_CONTENT_SEARCH_EXTENSIONS` |
| **Symbols** | Indexed keyword/variable/file search (View → Symbols / palette); separate from Find in Files |
| **Test Explorer** | Lazy suite tree (expand loads children), virtualized list; run test/suite/all/failed; confirm when estimated count exceeds threshold (default 100, `ROBOT_STUDIO_LARGE_RUN_THRESHOLD`); live filter + status |
| **Execution** | Run file or project; large project/tag runs require explicit confirmation (backend 409 + UI); live WebSocket logs; stop; history; finish stays on current view with View Report toast; **Failed Tests** after each run with Jump to Source + Re-run Test |
| **Robot Doctor** | Project health findings with Jump to source (Quick Fix hidden until real) || **Explorer file ops** | Multi-select (⌘/Ctrl / Shift), new file/folder (`.robot` files seeded with Settings/Variables/Test Cases/Keywords scaffold), inline rename (including case-only like `libs` → `Libs`), bulk delete, duplicate, copy path(s), reveal in OS, drag-move via live events |
| **Live workspace** | FS/index/git/env/progress events over `/workspace/events`; explorer incremental refresh; external edit / deleted-file dialogs; auto Git + Test Explorer refresh |
| **Reports** | Runs listed by run number from `.robotstudio/reports/Run-*` (legacy root `Reports/` still readable via stored paths); pass/fail stats; open `report.html` / `log.html` / `output.xml` from run details |
| **Terminal** | Bottom-panel PTY (login shell) rooted at the project folder; restart / kill from the tab chrome |
| **Git** | Scoped to the **active project** (never silently attaches to a parent monorepo); status (incl. untracked), stage, commit, branches, history, diff; Init creates a repo in the project; remote actions when a repo exists |
| **Plugins** | Builtin capabilities + plugin manager UI (load / enable / details) |
| **Status** | Project context, `ROBOT` / `PYTHON` versions (backend connection is not shown) |
| **UX guidance** | Actionable dialogs for missing project/env; gated CTAs; clickable run status → Tests; shared EmptyState + skeleton loaders; friendly timeout copy |
| **Chrome** | Quiet toolbar (project · environment · branch · Run / Run Project / Stop, git remotes behind ⋯); native window menu bar (File / Edit / View / Go / Run / Terminal) replaces the old editor action strip |
| **Errors** | Failure dialogs state what happened and how to fix it; raw exception text stays behind **Show details** |

---

## Prerequisites

- **Flutter** 3.x with desktop enabled (`macos`, `linux`, or `windows`)
- **Python** 3.11+
- **Git** (for Source Control features)
- Optional: [uv](https://github.com/astral-sh/uv) for faster backend installs

---

## Getting Started

### Packaged app (closed beta)

Beta users should **double-click** the app — not start a Python process by hand.

| Platform | Artifact | Launch |
|----------|----------|--------|
| macOS | `dist/macos/Robot Studio.app` (also zipped) | Double-click **Robot Studio.app** |
| Windows | `dist/windows/RobotStudio/RobotStudio.exe` (also zipped) | Double-click **RobotStudio.exe** |

Build packages from the repo root:

```bash
make package-macos      # → dist/macos/Robot Studio.app
make package-windows   # → dist/windows/RobotStudio/ (run on Windows)
make package           # this OS
```

The app embeds a frozen backend sidecar and starts it on launch. Quit stops it via a pid file + native terminate hooks (Flutter lifecycle alone is unreliable on desktop). Data lives under `~/.robot-studio`.

### Developer loop (two terminals)

While iterating on the code, keep using the unbundled loop. The app connects to `http://127.0.0.1:8765` and will **not** spawn a sidecar when that backend is already healthy.

### Makefile (recommended)

From the **repository root**:

```bash
make help              # list targets
make setup             # backend/.venv + flutter pub get
make backend           # start API on :8765 (foreground)
make run               # flutter run -d macos|linux|windows
make build             # flutter build <device>
make test              # pytest + flutter test
make test-integration  # E2E (or: make test-integration SUITE=startup_test.dart)
make package           # double-click app for this OS
make package-macos     # dist/macos/Robot Studio.app
make package-windows   # dist/windows/RobotStudio/
make health            # curl /api/v1/health
make backend-stop      # kill listener on PORT (default 8765)
```

Override device/port: `make run DEVICE=linux` · `make backend PORT=8766`.

### 1. Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
pip install -e ".[dev]"
python -m robot_studio.main
```

Or with uv:

```bash
cd backend
uv venv
source .venv/bin/activate
uv pip install -e ".[dev]"
python -m robot_studio.main
```

You can also use the console script after install:

```bash
robot-studio-backend
```

**Health check**

```bash
curl http://127.0.0.1:8765/api/v1/health
```

Expected shape (fields may grow):

```json
{
  "status": "ok",
  "version": "0.1.0",
  "modules": ["workspace", "project", "environment", "..."]
}
```

### 2. Frontend

```bash
cd frontend
flutter pub get
flutter run -d macos    # or: linux / windows
```

The status bar shows the active project name and `ROBOT` / `PYTHON` versions from the environment. When the backend is unreachable it shows **BACKEND UNAVAILABLE** (connected state stays quiet). Health is rechecked every ~2s while offline and ~15s while connected (three consecutive failures before marking offline), so the shell recovers without restarting the UI. Open or create a **project** first — environments and runs are scoped to it. Create Project / Manage Environments are disabled on the welcome screen until a project is open.

More frontend detail: [frontend/README.md](./frontend/README.md).

---

## Configuration

Backend settings use the `ROBOT_STUDIO_` environment prefix (`backend/robot_studio/core/config.py`):

| Variable | Default | Meaning |
|----------|---------|---------|
| `ROBOT_STUDIO_HOST` | `127.0.0.1` | Bind address |
| `ROBOT_STUDIO_PORT` | `8765` | HTTP / WebSocket port |
| `ROBOT_STUDIO_DATA_DIR` | `~/.robot-studio` | SQLite DB, plugins, local data |
| `ROBOT_STUDIO_DEBUG` | `false` | Debug mode |
| `ROBOT_STUDIO_LARGE_RUN_THRESHOLD` | `100` | Ask for confirmation before project/tag runs that would execute more than this many tests |
| `ROBOT_STUDIO_CONTENT_SEARCH_EXTENSIONS` | `.robot,.resource,.py,.yaml,.yml,.txt,.md,.json,.tsv,.csv` | File suffixes scanned by Find in Files |

Database path: `{data_dir}/robot-studio.db`.

Integration tests may also set `ROBOT_STUDIO_PYTHON` / `INTEGRATION_PYTHON` so environment creation uses a known interpreter. See [frontend/integration_test/README.md](./frontend/integration_test/README.md).

---

## Typical workflow

1. **New Project** or **Open Project** (any folder — Studio initializes `.robotstudio/` inside it; no wrapper workspace. Non-Robot-looking folders warn first with **Continue anyways**). **New Project** opens one dialog for name + location (prefilled, with **Browse…**), then always creates a standalone project and opens it fresh, even if another project is already open; adding to a multi-project container is the separate **New Project in Workspace** command. **Open Workspace** / **New Workspace** remain under Advanced for multi-project containers.
2. Opening a project is immediate; environment setup, indexing, and git refresh continue in the background. If no Python environment is registered, a non-blocking bottom-right toast titled **Python environment required** offers Create Environment / Select Existing (dismiss with ✕), and suggests an existing `.venv` when found. **Create Environment** from that toast installs Robot Framework (same default as the Create dialog). If **no Python interpreter** is installed on the machine, that toast becomes **Python is not installed** with **How to Install** (Homebrew / python.org / apt) instead of a dead-end Create button. If interpreter discovery itself fails (backend error/offline), the toast becomes **Could not detect Python** with install / create / select actions — it does not assume Python is present.
3. Create or activate a **Python environment**; install Robot Framework and libraries via the package manager. Run is blocked when the active environment is **missing on disk** (`available: false`) — recreate or select another before running. If you delete a project in Finder and recreate it at the same path, Studio mints a **new** durable identity under `.robotstudio/` (identity is never derived from the path), so ghost “missing” venvs and stale Reports from the previous folder life do not reappear.
4. Open `.robot` files in the editor; rebuild the **index** if keyword search looks empty (BuiltIn keywords such as `Log` are always searchable).
5. **Run** from the toolbar or **Tests** explorer (suite / test / tag / failed); watch output on the **Tests** view (click the run status badge to jump there). Use the bottom **Terminal** for an interactive shell in the project folder.
6. Open **Reports** for history and HTML output; use **Source Control** if the project is a Git repo.
7. If a run fails on a missing known library (Browser, SeleniumLibrary, …), use the Install snackbar or Package Manager.

---

## Project structure

```
robot-studio/
├── ARCHITECTURE.md              # Design: layers, modules, milestones
├── README.md                    # This file (repo overview)
├── Makefile                     # setup / backend / run / build / test shortcuts
├── scripts/
│   └── run_integration_tests.sh # Live backend + Flutter integration suites
├── backend/
│   ├── pyproject.toml
│   ├── requirements.txt
│   ├── tests/                   # pytest (API + unit)
│   └── robot_studio/
│       ├── main.py
│       ├── api/                 # Routes, schemas, REST gateway
│       ├── application/         # Use-case services
│       ├── core/                # Config, DI container, events, plugins
│       ├── domain/              # Models + port interfaces
│       └── infrastructure/      # SQLite, indexers, runner, git, plugins…
└── frontend/
    ├── README.md                # Flutter app overview & tests
    ├── lib/
    │   ├── core/                # Gateway, models, theme, logging
    │   ├── main.dart
    │   └── presentation/        # Shell, editor, git, packages, reports…
    ├── test/                    # Widget / unit tests
    └── integration_test/        # End-to-end desktop suites (+ README)
```

### Backend layers

| Layer | Role |
|-------|------|
| **api** | FastAPI routers, Pydantic schemas, `RestGateway` |
| **application** | Orchestration (workspace, project, execution, index, git, plugins…) |
| **domain** | Entities and abstract ports (`Runner`, `IndexStore`, `Installer`, …) |
| **infrastructure** | SQLite repos, subprocess runner, robot/python indexers, Git CLI, plugin loader |
| **core** | Settings, container, event bus, plugin host |

### Frontend layers

| Area | Role |
|------|------|
| **TransportGateway** | UI depends on this contract, not raw HTTP |
| **RestTransportGateway** | Current REST + WebSocket implementation |
| **presentation/** | Shell, panels, editor, managers (mostly props-driven widgets) |
| **controllers/** | Shell state helpers (workspace, editor, execution) |

### Main API surface (`/api/v1`)

| Prefix | Purpose |
|--------|---------|
| `/health` | Liveness + registered modules |
| `/workspaces` | Create, open, recent, close |
| `/projects` | Create/import/open/recent (no project-type templates) |
| `/environments` | Create, activate, clone, delete |
| `/packages` | List, search, install, uninstall |
| `/execution` | Run, stop (idempotent), history (excludes aborted startups); `/execution/stream` WebSocket |
| `/workspace/events` | Live FS / index / git / environment WebSocket fan-out |
| `/reports` | Runs, dashboard, artifacts |
| `/index` | Rebuild, status |
| `/search/symbols`, `/search/content` | Indexed symbol search; plain-text Find in Files |
| `/analysis` | Semantic engine + Inspection Engine (`Finding`s); graph queries under `/analysis/graph/*`; execution knowledge under `/analysis/execution/*` (incl. per-run `run-failures`) |
| `/doctor` | Robot Doctor Project Health Center (`profiles`, `run`, `report/{id}`, `history`) |
| `/language` | Definition, hover, references, completion, diagnostics |
| `/files` | Read/write, tree listing (lazy `depth=0` + `has_children`, workspace-scoped) |
| `/git` | Status, stage, commit, branches, history, remotes |
| `/plugins` | List, enable/disable, details |

---

## Development

### Backend tests

```bash
make test-backend
# or:
cd backend
source .venv/bin/activate
pip install -e ".[dev]"          # if needed
pytest -q
# or: uv run pytest -q
```

API fixtures call `Container.shutdown()` (stops the index watcher + git background tasks) before the ASGI client closes. Tests force `PollingFileWatcher` via `tests/conftest.py` so watchdog observer threads cannot livelock pytest-asyncio teardown.

Focused examples:

```bash
pytest tests/test_workspace_api.py tests/test_indexing.py -q
pytest tests/test_analysis_engine.py -q
pytest tests/test_execution_knowledge.py -q
pytest tests/test_doctor.py -q
pytest tests/test_execution_api.py tests/test_git_api.py -q
```

### Frontend unit / widget tests

```bash
make test-frontend
# or:
cd frontend
flutter pub get
flutter test
flutter analyze
```

See [frontend/README.md](./frontend/README.md) for module map and notable widget tests.

### Integration tests

These launch the real desktop UI against a live backend. Prefer the helper script (starts an isolated backend on a free port — important on macOS sandbox):

```bash
# From repo root; requires backend/.venv
make test-integration
make test-integration SUITE=startup_test.dart
# or:
./scripts/run_integration_tests.sh
./scripts/run_integration_tests.sh startup_test.dart
```

Details and suite list: [frontend/integration_test/README.md](./frontend/integration_test/README.md).

---

## Current status

Core IDE milestones through execution, reports, indexing, language features, Git, and plugins are in place. The product is in **public-beta usability hardening** against `qa-bench/QA-ISSUES.md` — focusing on the daily Open Project → Environment → F5 → Results → Doctor loop (no fake runs, project-rooted Explorer, actionable Robot-missing dialogs, keyboard Run/Stop/Doctor).

| Milestone | Scope | Status |
|-----------|--------|--------|
| **M1** | Architecture, app shell, health API | Done |
| **M1.5** | Architecture v2 (Event Bus, Plugin Host, Indexing, transport) | Done |
| **M2** | Workspace management | Done |
| **M3** | Project management | Done |
| **M4** | Environment manager | Done |
| **M5** | Package manager | Done |
| **M6** | Indexing + language service (completion, hover, …) | Done |
| **M6.5** | Robot Analysis Engine (semantic graphs + `/analysis` APIs) | Done (infrastructure) |
| **M6.6** | Robot Doctor (Project Health Center + `/doctor` APIs + UI) | Done |
| **M7** | Test execution + WebSocket logs | Done |
| **M8** | Reports | Done |
| **M9+** | Settings / AI / packaging polish | Partial (Settings hidden until implemented; AI deferred; **desktop packaging shipped for closed beta** — `make package-macos` / `package-windows`) |
| **M10** | Intelligent editor (parsing bridge, diagnostics, navigation) | In progress / shipping |
| **M11** | Plugin framework + manager UI | In progress / shipping |
| **M12** | Git source control | In progress / shipping |

`ARCHITECTURE.md` (v2.1) is the **design north star** and now tracks **implemented vs planned** status. Treat [README.md](./README.md) as the **product/runbook snapshot**.

### Related docs

| Document | Contents |
|----------|----------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Layers, modules, APIs, risks, roadmap |
| [frontend/README.md](./frontend/README.md) | Flutter app structure, run, widget tests |
| [frontend/integration_test/README.md](./frontend/integration_test/README.md) | E2E suites and harness |

### Keeping docs in sync

After feature or UX implementations, update **all three** READMEs when behavior, setup, or tests change:

1. [README.md](./README.md) (this file)
2. [frontend/README.md](./frontend/README.md)
3. [frontend/integration_test/README.md](./frontend/integration_test/README.md)

---

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Toolbar / actions unavailable | Start the backend; the UI retries `/health` every ~2s while offline (~15s while connected, with a 3-failure threshold). Confirm with `curl http://127.0.0.1:8765/api/v1/health` |
| Port already in use | `ROBOT_STUDIO_PORT=8766 python -m robot_studio.main` (and point the client at that port if configured) |
| Empty keyword index | Open a project, ensure `.robot` files exist, run **Rebuild index**; BuiltIn keywords should still appear in search |
| Run disabled / guidance dialog | Select a project (and activate an environment) — Run stays gated until prerequisites exist |
| Run fails on missing library | Install via Package Manager (or use the post-run Install snackbar for known libraries) |
| Git Fetch/Pull/Push hidden | The project is not a Git repository (the toolbar ⋯ menu only appears for repos) |
| Project/workspace folder deleted in Finder | Within ~2s the app shows a **no longer exists** dialog (Dismiss / Locate / Close). Saving into a deleted root is refused rather than silently recreating the folder — restore it from Trash, or close and reopen |
| Terminal shows `[process exited with code 255]` | The macOS app was built with App Sandbox on, which blocks spawning a shell. `macos/Runner/*.entitlements` must not set `com.apple.security.app-sandbox`; then do a full `flutter run` (hot reload does not re-sign the app) |
| Integration tests can’t start Python (macOS) | Use `./scripts/run_integration_tests.sh` so the backend is started outside the app sandbox |

---

## License

TBD
