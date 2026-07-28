# Robot Studio

A cross-platform desktop IDE for [Robot Framework](https://robotframework.org/) development.

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
| **Projects** | Primary entry: New / Open / Recent Projects; open any Robot Framework folder (`.robotstudio/` in-place); new projects get empty `tests/` / `resources/` / `variables/` folders — no template types |
| **Workspaces** | Advanced multi-project containers (Open / New / Recent); still the domain container behind the scenes |
| **Environments** | Create / import / clone / activate; non-blocking prompt on open; detects `.venv` / `venv` / `env` / `Environments/*` |
| **Packages** | List installed packages, search PyPI, install / update / uninstall |
| **Editor** | Multi-tab Robot editor, find/replace, live diagnostics; document outline under Explorer |
| **Language intelligence** | Completions, hover, go-to-definition, references, document symbols |
| **Problems** | Bottom Problems panel synced while editing; jump to line/column; status-bar ERRORS/WARNINGS shortcut |
| **Command palette** | ⌘K / Ctrl+K (toolbar search) for commands, recent files, project files, and symbols |
| **Indexing** | Background on open (incremental); full rebuild on demand; excludes `.venv` / `node_modules` / `.git` |
| **Test Explorer** | Browse suites/tests/tasks/tags; run test, suite, tag, failed; live filter + status |
| **Execution** | Run file or project; live WebSocket logs; stop; history |
| **Explorer file ops** | New file/folder (`.robot` files seeded with Settings/Variables/Test Cases/Keywords scaffold), inline rename, delete, duplicate, copy path, reveal in OS, drag-move via live events |
| **Live workspace** | FS/index/git/env events over `/workspace/events`; explorer incremental refresh; external edit / deleted-file dialogs; auto Git + Test Explorer refresh |
| **Reports** | Recent runs, pass/fail stats; open `report.html` / `log.html` / `output.xml` from run details |
| **Git** | Status (incl. untracked), stage, commit, branches, history, diff; remote actions when a repo exists |
| **Plugins** | Builtin capabilities + plugin manager UI (load / enable / details) |
| **Status** | Project context, `ROBOT` / `PYTHON` versions (backend connection is not shown) |
| **UX guidance** | Actionable dialogs for missing project/env; gated CTAs; clickable run status → Execution Logs; shared EmptyState + skeleton loaders; friendly timeout copy |
| **Chrome** | Quiet toolbar (project · environment · branch · Run / Run Project / Stop, git remotes behind ⋯); editor strip keeps Save / Save All / Format / Find / Wrap and moves language navigation to its ⋯ menu |
| **Errors** | Failure dialogs state what happened and how to fix it; raw exception text stays behind **Show details** |

---

## Prerequisites

- **Flutter** 3.x with desktop enabled (`macos`, `linux`, or `windows`)
- **Python** 3.11+
- **Git** (for Source Control features)
- Optional: [uv](https://github.com/astral-sh/uv) for faster backend installs

---

## Getting Started

Run the backend and frontend in two terminals. The app connects to `http://127.0.0.1:8765` on launch.

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

The status bar shows the active project name and `ROBOT` / `PYTHON` versions from the environment — not backend CONNECTED/OFFLINE chrome. Health is rechecked every ~2s while offline and ~15s while connected (three consecutive failures before marking offline), so the shell recovers without restarting the UI. Open or create a **project** first — environments and runs are scoped to it. Create Project / Manage Environments are disabled on the welcome screen until a project is open.

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

Database path: `{data_dir}/robot-studio.db`.

Integration tests may also set `ROBOT_STUDIO_PYTHON` / `INTEGRATION_PYTHON` so environment creation uses a known interpreter. See [frontend/integration_test/README.md](./frontend/integration_test/README.md).

---

## Typical workflow

1. **New Project** or **Open Project** (any folder — Studio initializes `.robotstudio/` inside it; no wrapper workspace. Non-Robot-looking folders warn first with **Continue anyways**). **Open Workspace** / **New Workspace** remain under Advanced for multi-project containers.
2. Opening a project is immediate; environment setup, indexing, and git refresh continue in the background. If no Python environment is registered, a non-blocking bottom-right toast titled **Python environment required** offers Create Environment / Select Existing (dismiss with ✕), and suggests an existing `.venv` when found.
3. Create or activate a **Python environment**; install Robot Framework and libraries via the package manager.
4. Open `.robot` files in the editor; rebuild the **index** if keyword search looks empty (BuiltIn keywords such as `Log` are always searchable).
5. **Run** from the toolbar or **Tests** explorer (suite / test / tag / failed); watch **Execution Logs** in the bottom panel (click the run status badge to jump there).
6. Open **Reports** for history and HTML output; use **Source Control** if the project is a Git repo.
7. If a run fails on a missing known library (Browser, SeleniumLibrary, …), use the Install snackbar or Package Manager.

---

## Project structure

```
robot-studio/
├── ARCHITECTURE.md              # Design: layers, modules, milestones
├── README.md                    # This file (repo overview)
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
| `/execution` | Run, stop, history; `/execution/stream` WebSocket |
| `/workspace/events` | Live FS / index / git / environment WebSocket fan-out |
| `/reports` | Runs, dashboard, artifacts |
| `/index`, `/search` | Rebuild, status, symbol search |
| `/language` | Definition, hover, references, completion, diagnostics |
| `/files` | Read/write, tree listing (lazy `depth=0` + `has_children`, workspace-scoped) |
| `/git` | Status, stage, commit, branches, history, remotes |
| `/plugins` | List, enable/disable, details |

---

## Development

### Backend tests

```bash
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
pytest tests/test_execution_api.py tests/test_git_api.py -q
```

### Frontend unit / widget tests

```bash
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
./scripts/run_integration_tests.sh

# Single suite
./scripts/run_integration_tests.sh startup_test.dart
```

Details and suite list: [frontend/integration_test/README.md](./frontend/integration_test/README.md).

---

## Current status

Core IDE milestones through execution, reports, indexing, language features, Git, and plugins are in place. The product is in **active usability hardening** against the public-beta review backlog (critical/functional/UX items such as cold-start status, reports panel, keyword index BuiltIns, guidance dialogs, AI chrome removal).

| Milestone | Scope | Status |
|-----------|--------|--------|
| **M1** | Architecture, app shell, health API | Done |
| **M1.5** | Architecture v2 (Event Bus, Plugin Host, Indexing, transport) | Done |
| **M2** | Workspace management | Done |
| **M3** | Project management | Done |
| **M4** | Environment manager | Done |
| **M5** | Package manager | Done |
| **M6** | Indexing + language service (completion, hover, …) | Done |
| **M7** | Test execution + WebSocket logs | Done |
| **M8** | Reports | Done |
| **M9+** | Settings / AI / packaging polish | Partial (Settings hidden until implemented; AI deferred; bundled backend auto-start deferred to end) |
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
| Integration tests can’t start Python (macOS) | Use `./scripts/run_integration_tests.sh` so the backend is started outside the app sandbox |

---

## License

TBD
