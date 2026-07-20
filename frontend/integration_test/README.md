# Robot Studio — Integration Tests

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

### Recommended (repo script)

From the **repository root**. Starts an isolated backend on a free port (required on macOS — the app sandbox cannot spawn Python), passes `--dart-define` values, and tears down after each suite:

```bash
./scripts/run_integration_tests.sh

# Single suite (filename under integration_test/)
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

Some suites (environment creation, package install, execution) may take several minutes on first run.

---

## Harness & fixtures

| Path | Purpose |
|------|---------|
| `helpers/backend_process.dart` | Starts/stops backend with isolated `ROBOT_STUDIO_DATA_DIR` |
| `helpers/integration_api_client.dart` | REST setup, verification, async polling |
| `helpers/integration_harness.dart` | Shared lifecycle, app launch, seed helpers |
| `helpers/integration_fixtures.dart` | Shared fixture paths / seed data |
| `helpers/ui_helpers.dart` | UI interaction and condition-based waits |
| `helpers/performance_tracker.dart` | Timing logs (no pass/fail thresholds) |
| `fixtures/sample.robot` | Sample suite |
| `fixtures/test_plugin/` | Fake plugin (`plugin.json` + `plugin.py`) |

Tests avoid arbitrary `sleep()` and wait for visible UI states instead.

---

## Notes

- Widget / unit tests live in `frontend/test/` and run separately: `flutter test` (see [../README.md](../README.md)).
- Git suites need the system `git` CLI (same as production Source Control).
- After adding or renaming suites, update **this README** and the suite table in the root / frontend READMEs if they mention coverage.

---

## Keeping docs in sync

When you change E2E harness behavior, suite list, or how tests are launched, update:

1. [../../README.md](../../README.md)
2. [../README.md](../README.md)
3. This file (`frontend/integration_test/README.md`)
