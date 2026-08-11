# Robot Studio — Integration Tests

## TODO:
Ship packaging (deferred): Bundle a frozen Python backend sidecar; Flutter (or native launcher) auto-spawns it on app start, health-waits, and stops it on quit. End users never start the backend manually. MacOS sandbox/spawn entitlements need explicit handling.

End-to-end Flutter **desktop** tests for Robot Studio. Suites launch the real UI against a **live Python backend** with an isolated data directory.

Parent docs: [../../README.md](../../README.md) · [../README.md](../README.md)

---

## Prerequisites

1. Backend virtualenv with dependencies installed:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
```

2. Flutter SDK with **desktop** support (`macos` / `linux` / `windows`).

3. Optional environment variables (see below).

---

## Running

### Recommended (repo script or Make)

From the **repository root**. Starts an isolated backend on a free port (required on macOS — the app sandbox cannot spawn Python), passes `--dart-define` values, and tears down after each suite:

```bash
make test-integration
make test-integration SUITE=startup_test.dart

# Equivalent:
./scripts/run_integration_tests.sh
./scripts/run_integration_tests.sh startup_test.dart
```

Requires `backend/.venv` (or set `ROBOT_STUDIO_PYTHON` to another interpreter that can run the backend).

### Direct Flutter (advanced)

Only if the backend is already reachable at the URL you pass:

```bash
cd frontend
flutter pub get

flutter test -d macos integration_test/startup_test.dart \
  --dart-define=INTEGRATION_BACKEND_URL=http://127.0.0.1:8765

# All suites (each must share a running backend or use the script instead)
flutter test -d macos integration_test/
```

Prefer the script for CI and local full runs.

---

## Environment variables

| Variable | Purpose |
|----------|---------|
| `ROBOT_STUDIO_PYTHON` | Python executable for backend process and venv creation |
| `INTEGRATION_PYTHON` | Interpreter used when tests create environments (defaults with `ROBOT_STUDIO_PYTHON`) |
| `ROBOT_STUDIO_PORT` | Fixed backend port for the script (optional; default picks a free port) |
| `ROBOT_STUDIO_REPO_ROOT` | Repository root (set automatically by the script) |

Dart defines injected by the script:

| Define | Purpose |
|--------|---------|
| `INTEGRATION_BACKEND_URL` | e.g. `http://127.0.0.1:<port>` |
| `ROBOT_STUDIO_BACKEND_PORT` | Same port |
| `ROBOT_STUDIO_REPO_ROOT` | Absolute repo root |

---

## Suites

| File | Focus |
|------|--------|
| `functional_shell_test.dart` | Functional TC SH-01…SH-08 (shell / status / connectivity) |
| `functional_workspace_test.dart` | Functional TC WS-01…WS-10 (project-first welcome, workspace advanced create/open/recent) |
| `functional_project_test.dart` | Functional TC PR-01…PR-10 (create/import/select/run gating) |
| `functional_explorer_test.dart` | Functional TC EX-01…EX-08 (lazy file tree, tabs, save); Pre-M14 file ops covered by widget tests |
| `functional_environment_test.dart` | Functional TC EN-01…EN-10 (create/activate/import/clone/delete) |
| `functional_packages_test.dart` | Functional TC PK-01…PK-09 (list/search/install; some skips) |
| `functional_editor_test.dart` | Functional TC ED-01…ED-10 (open/tabs/save/problems jump) |
| `functional_language_test.dart` | Functional TC LG-01…LG-10 (diagnostics/completions/hover/refs) |
| `functional_index_test.dart` | Functional TC IX-01…IX-10 (index/search/keywords/tests panel) |
| `functional_command_palette_test.dart` | Functional TC CP-01…CP-07 (command palette) |
| `functional_execution_test.dart` | Functional TC XC-01…XC-12 (run/stop/history/gating) |
| `functional_reports_test.dart` | Functional TC RP-01…RP-09 (reports list/details/delete) |
| `functional_git_test.dart` | Functional TC GT-01…GT-10 (source control; local bare remote for GT-10) |
| `functional_plugins_test.dart` | Functional TC PL-01…PL-07 (plugins; PL-07 skip) |
| `functional_ux_test.dart` | Functional TC UX-01…UX-08 (guidance / gating) |
| `functional_crosscut_test.dart` | Functional TC XR-01…XR-06 (smoke / stress; XR-05 skip) |
| `startup_test.dart` | App launch, backend connection, welcome shell |
| `workspace_flow_test.dart` | Create / open workspace |
| `project_flow_test.dart` | Create / import / select projects |
| `environment_flow_test.dart` | Create / activate environments |
| `package_manager_test.dart` | Package list / install flows |
| `editor_test.dart` | Open files, editor basics |
| `intelligent_editor_test.dart` | Language features / navigation |
| `execution_test.dart` | Run / stop / log streaming |
| `reports_test.dart` | Reports list and details |
| `git_test.dart` | Source control (requires local `git`) |
| `plugin_system_test.dart` | Plugin manager / fixtures |
| `regression_test.dart` | Cross-cutting smoke / regressions |

Functional suites map 1:1 to modules in [docs/internal/functional-test-cases.md](../../docs/internal/functional-test-cases.md). Skips: SH-02/SH-03 (external backend stop/restart), WS-02/WS-09 (native FilePicker), PK-04/PK-07/PK-09 (env/network/deferred), PL-07 / XR-05 (cannot stop external backend mid-suite). GT-10 seeds a local bare remote via `POST /git/seed-local-remote`.

Some suites (environment creation with `installRobot: true`, package install, execution) may take several minutes on first run — watch for `[perf] environment_create_api` rather than assuming a hang.

---

## Harness & fixtures

| Path | Purpose |
|------|---------|
| `helpers/backend_process.dart` | Starts/stops backend with isolated `ROBOT_STUDIO_DATA_DIR` |
| `helpers/integration_api_client.dart` | REST setup, verification, async polling |
| `helpers/integration_harness.dart` | Shared lifecycle, app launch, seed helpers (`openRecentWorkspace` waits for welcome to dismiss — not the workspace title, which disappears when a project auto-opens) |
| `helpers/integration_fixtures.dart` | Shared fixture paths / seed data |
| `helpers/ui_helpers.dart` | UI interaction and condition-based waits (incl. `tapEditorFormat` / `tapEditorFind` / `tapEditorMenuAction` via the command palette) |
| `helpers/performance_tracker.dart` | Timing logs (no pass/fail thresholds) |
| `fixtures/sample.robot` | Sample suite |
| `fixtures/test_plugin/` | Fake plugin (`plugin.json` + `plugin.py`) |

Live workspace events (`/api/v1/workspace/events`) are covered by backend `tests/test_workspace_events.py` and Flutter `test/workspace_live_events_test.dart`; explorer/git E2E suites exercise the UI side indirectly.

Tests avoid arbitrary `sleep()` and wait for visible UI states instead.

After the pre-M14 UX polish pass, suites reach language navigation through the editor
overflow menu is gone — use `tapEditorMenuAction(tester, 'definition' | 'peek' | 'references' | 'hover' | …)` (command palette) or the window **Go** / **Edit** menus
rather than permanent toolbar buttons, and the bottom panel has Terminal / 
Problems — run output is on the Tests view; SH-08 asserts Execution Logs is gone.

---

## Notes

- Widget / unit tests live in `frontend/test/` and run separately: `flutter test` (see [../README.md](../README.md)).
- Git suites need the system `git` CLI (same as production Source Control).
- After UX polish / project-type removal: connection chrome is not asserted as CONNECTED/OFFLINE (offline uses **BACKEND UNAVAILABLE**); New Project is name-only (no template picker); editor actions use the window menu bar / command palette (`wait` on `editor.page`, `tapEditorFormat` / `tapEditorFind` / `tapEditorMenuAction`); Settings/Output stubs are expected absent (Terminal is a real bottom-panel tab).

---

## Keeping docs in sync

When you change E2E harness behavior, suite list, or how tests are launched, update:

1. [../../README.md](../../README.md)
2. [../README.md](../README.md)
3. This file (`frontend/integration_test/README.md`)
