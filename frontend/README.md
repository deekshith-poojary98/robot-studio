# Robot Studio — Frontend

Flutter **desktop** UI for Robot Studio (macOS / Linux / Windows). The app talks to the local Python backend through `TransportGateway` (REST + WebSocket today).

Repo overview and backend setup: [../README.md](../README.md)  
Architecture: [../ARCHITECTURE.md](../ARCHITECTURE.md)  
Integration tests: [integration_test/README.md](./integration_test/README.md)

---

## Prerequisites

- Flutter 3.x with desktop support enabled
- Backend running at `http://127.0.0.1:8765` (see root README), unless you override the URL for tests

---

## Run

```bash
cd frontend
flutter pub get
flutter run -d macos    # or linux / windows
```

On launch the shell health-checks the backend and shows **Connected** / **Offline** in the toolbar. Create or open a **workspace** before projects, environments, packages, or runs.

---

## Layout

```
frontend/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── api/                 # Low-level HTTP helpers
│   │   ├── config/              # Backend URL / dart-defines
│   │   ├── gateway/             # TransportGateway + REST impl + DTOs
│   │   ├── logging/
│   │   └── theme/
│   └── presentation/
│       ├── shell/               # AppShell, status bar, controllers
│       ├── sidebar/             # Activity rail (Explorer, Tests, Git, …)
│       ├── toolbar/
│       ├── panels/              # Side + bottom panels (console, logs, problems)
│       ├── workspace/           # Welcome, explorer
│       ├── editor/              # Robot code editor + language widgets
│       ├── execution/           # Run page + history
│       ├── reports/
│       ├── packages/
│       ├── environment/
│       ├── project/
│       ├── git/
│       ├── plugins/
│       ├── search/
│       └── widgets/             # Shared UI (guidance dialog, tree, badges, …)
├── test/                        # Widget / unit tests
└── integration_test/            # Live backend E2E suites
```

### Key concepts

| Piece | Role |
|-------|------|
| `TransportGateway` | UI contract for all backend calls |
| `RestTransportGateway` | Current implementation (injectable for tests) |
| `AppShell` | Top-level navigation, workspace lifecycle, run/git/package wiring |
| Shell controllers | Workspace / editor / execution state helpers |
| `showGuidanceDialog` | Actionable “next step” dialogs (open workspace, manage env, …) |

### Sidebar panels

Explorer · Search · Tests · Keywords · Packages · Plugins · Source Control · Reports  

AI is **not** in the rail until the feature ships. Settings remains a stub (“coming soon”).

---

## UX notes (current)

- Welcome: **Create Robot Project** / **Manage Environments** disabled without a workspace; recent names have path tooltips.
- Opening a workspace auto-selects a recent/first project when possible.
- **Run** / **Run Project** disabled until a project is selected; missing env/workspace uses guidance dialogs with primary actions.
- Toolbar run-status badge opens **Execution Logs**.
- Status bar shows `ROBOT` / `PYTHON` / `ENV` from the active environment (no API version watermark).
- Missing-library run failures (Browser, SeleniumLibrary, …) can prompt Install via snackbar.

---

## Tests

### Widget / unit

```bash
cd frontend
flutter test
flutter analyze
```

Notable suites under `test/`:

| File | Covers |
|------|--------|
| `widget_test.dart` | Welcome, dialogs, managers, toolbar, editor shells |
| `status_bar_test.dart` | ENV / ROBOT / PYTHON labels |
| `ux_guidance_test.dart` | Guidance dialog + recent-item tooltips |
| `execution_stream_status_test.dart` | Cold-start idle vs stale run status |
| `reports_side_panel_test.dart` | Reports side panel uses real runs |
| `git_widget_test.dart` | Source control widgets |
| `plugin_manager_test.dart` | Plugin manager layout / rows |
| `problems_panel_test.dart` | Problems panel |

### Integration (E2E)

Prefer the repo script so macOS sandbox can reach Python:

```bash
# From repository root
./scripts/run_integration_tests.sh
./scripts/run_integration_tests.sh startup_test.dart
```

Full suite list and harness: [integration_test/README.md](./integration_test/README.md).

---

## Configuration (dart-define)

Used mainly by integration tests / harness:

| Define | Purpose |
|--------|---------|
| `INTEGRATION_BACKEND_URL` | Backend base URL |
| `ROBOT_STUDIO_BACKEND_PORT` | Port paired with the test backend |
| `ROBOT_STUDIO_REPO_ROOT` | Repo root for fixtures / scripted backend |

Default desktop runs use `http://127.0.0.1:8765` via app config.

---

## Keeping docs in sync

When you change frontend behavior, setup, or tests, update:

1. [../README.md](../README.md)
2. This file (`frontend/README.md`)
3. [integration_test/README.md](./integration_test/README.md)
