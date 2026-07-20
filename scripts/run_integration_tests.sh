#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend"

if [[ ! -x "$BACKEND/.venv/bin/python" ]]; then
  echo "Backend venv not found at $BACKEND/.venv — create it before running integration tests." >&2
  exit 1
fi

export ROBOT_STUDIO_PYTHON="${ROBOT_STUDIO_PYTHON:-$BACKEND/.venv/bin/python}"
export INTEGRATION_PYTHON="${INTEGRATION_PYTHON:-$ROBOT_STUDIO_PYTHON}"
export ROBOT_STUDIO_REPO_ROOT="$ROOT"

find_free_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

wait_for_backend() {
  local attempts=0
  until curl -sf "${BASE_URL}/api/v1/health" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 90 ]]; then
      echo "Backend did not become ready at ${BASE_URL}" >&2
      return 1
    fi
    sleep 0.5
  done
}

start_backend() {
  local data_dir="$1"
  mkdir -p "$data_dir"
  (
    cd "$BACKEND"
    ROBOT_STUDIO_DATA_DIR="$data_dir" \
      ROBOT_STUDIO_HOST=127.0.0.1 \
      ROBOT_STUDIO_PORT="$PORT" \
      "$ROBOT_STUDIO_PYTHON" -m robot_studio.main
  ) &
  BACKEND_PID=$!
}

stop_backend() {
  if [[ -n "${BACKEND_PID:-}" ]]; then
    kill "$BACKEND_PID" 2>/dev/null || true
    wait "$BACKEND_PID" 2>/dev/null || true
    BACKEND_PID=""
    sleep 0.5
  fi
}

run_test_file() {
  local test_file="$1"
  local data_dir
  data_dir="$(mktemp -d "${TMPDIR:-/tmp}/robot_studio_it_backend.XXXXXX")"
  PORT="$(find_free_port)"
  BASE_URL="http://127.0.0.1:${PORT}"
  DART_DEFINES=(
    "--dart-define=ROBOT_STUDIO_REPO_ROOT=${ROOT}"
    "--dart-define=ROBOT_STUDIO_BACKEND_PORT=${PORT}"
    "--dart-define=INTEGRATION_BACKEND_URL=${BASE_URL}"
  )

  echo "==> Starting backend for ${test_file} on port ${PORT} (data: ${data_dir})"
  start_backend "$data_dir"
  if ! wait_for_backend; then
    stop_backend
    rm -rf "$data_dir"
    return 1
  fi

  set +e
  (
    cd "$FRONTEND"
    flutter test -d macos "$test_file" "${DART_DEFINES[@]}"
  )
  local exit_code=$?
  set -e

  stop_backend
  rm -rf "$data_dir"
  return "$exit_code"
}

cd "$FRONTEND"
flutter pub get

if [[ -n "${1:-}" ]]; then
  target="integration_test/${1}"
  if [[ "$1" == integration_test/* ]]; then
    target="$1"
  fi
  if [[ ! -f "$target" ]]; then
    echo "Integration test file not found: $target" >&2
    exit 1
  fi
  run_test_file "$target"
  exit $?
fi

failed=0
for test_file in integration_test/*_test.dart; do
  if ! run_test_file "$test_file"; then
    failed=1
  fi
done

exit "$failed"
