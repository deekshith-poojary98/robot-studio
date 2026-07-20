# Robot Studio Integration Tests

End-to-end Flutter integration tests for Milestones 2–12. These tests launch the real desktop UI against a live Python backend.

## Prerequisites

1. Backend virtualenv with dependencies installed:

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

2. Flutter SDK with desktop support enabled.

3. Optional environment variables:

- `ROBOT_STUDIO_PYTHON` — Python executable for backend and venv creation
- `INTEGRATION_PYTHON` — Python interpreter used when creating environments

## Running

From the `frontend/` directory:

```bash
flutter pub get

# Run a single suite
flutter test integration_test/startup_test.dart

# Run all integration suites
flutter test integration_test/
```

Or use the helper script from the repository root:

```bash
./scripts/run_integration_tests.sh

# Single suite (filename under integration_test/)
./scripts/run_integration_tests.sh startup_test.dart
```

The script starts an isolated backend on a free port (macOS app sandbox cannot spawn Python), passes `--dart-define` values to Flutter, and tears down after each suite.

## Environment variables

- `ROBOT_STUDIO_PYTHON` — Python executable for backend and venv creation
- `INTEGRATION_PYTHON` — Python interpreter used when creating environments
- `ROBOT_STUDIO_PORT` — Fixed backend port (optional; default picks a free port)
- `ROBOT_STUDIO_REPO_ROOT` — Repository root (set automatically by the script)

| Path | Purpose |
|------|---------|
| `helpers/backend_process.dart` | Starts/stops backend with isolated `ROBOT_STUDIO_DATA_DIR` |
| `helpers/integration_api_client.dart` | REST setup, verification, and async polling |
| `helpers/integration_harness.dart` | Shared lifecycle, app launch, seed helpers |
| `helpers/ui_helpers.dart` | UI interaction and condition-based waits |
| `helpers/performance_tracker.dart` | Timing logs (no pass/fail thresholds) |
| `fixtures/` | Sample robot suite and fake test plugin |

Tests avoid arbitrary `sleep()` calls and wait for visible UI states instead.

## Notes

- Widget tests in `test/` remain unchanged and run separately via `flutter test test/`.
- Some suites (environment creation, package install, execution) may take several minutes on first run.
- Git commits require local `git` CLI availability (same as production).
