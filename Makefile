# Robot Studio — common developer commands
#
# Usage: make <target>
#        make help

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BACKEND := $(ROOT)/backend
FRONTEND := $(ROOT)/frontend
VENV_PYTHON := $(BACKEND)/.venv/bin/python
PORT ?= 8765
HOST ?= 127.0.0.1
BASE_URL := http://$(HOST):$(PORT)

# Desktop device for flutter run / build (override: make run DEVICE=linux)
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  DEVICE ?= macos
else ifeq ($(UNAME_S),Linux)
  DEVICE ?= linux
else
  DEVICE ?= windows
endif

# Optional: ./scripts/run_integration_tests.sh <file>
SUITE ?=

.PHONY: help setup setup-backend setup-frontend \
	backend backend-stop health \
	run run-frontend build build-frontend \
	test test-backend test-frontend test-integration analyze \
	pub-get clean

.DEFAULT_GOAL := help

help: ## Show this help
	@echo "Robot Studio Make targets"
	@echo ""
	@echo "  DEVICE=$(DEVICE)  PORT=$(PORT)  HOST=$(HOST)"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup: setup-backend setup-frontend ## Create backend venv + flutter pub get

setup-backend: ## Create backend/.venv and install package (dev extras)
	@if [[ ! -x "$(VENV_PYTHON)" ]]; then \
		cd "$(BACKEND)" && python3 -m venv .venv; \
	fi
	cd "$(BACKEND)" && .venv/bin/pip install -r requirements.txt
	cd "$(BACKEND)" && .venv/bin/pip install -e ".[dev]"
	@echo "Backend ready: $(VENV_PYTHON)"

setup-frontend: ## flutter pub get
	cd "$(FRONTEND)" && flutter pub get

# ---------------------------------------------------------------------------
# Backend
# ---------------------------------------------------------------------------

backend: ## Start FastAPI backend (foreground, port $(PORT))
	@if [[ ! -x "$(VENV_PYTHON)" ]]; then \
		echo "Missing $(VENV_PYTHON) — run: make setup-backend" >&2; \
		exit 1; \
	fi
	cd "$(BACKEND)" && \
		ROBOT_STUDIO_HOST="$(HOST)" \
		ROBOT_STUDIO_PORT="$(PORT)" \
		"$(VENV_PYTHON)" -m robot_studio.main

backend-stop: ## Stop process listening on PORT ($(PORT))
	@pids=$$(lsof -nP -iTCP:$(PORT) -sTCP:LISTEN -t 2>/dev/null || true); \
	if [[ -z "$$pids" ]]; then \
		echo "No listener on $(PORT)"; \
	else \
		echo "Stopping PID(s) on $(PORT): $$pids"; \
		kill $$pids 2>/dev/null || true; \
		sleep 0.5; \
		kill -9 $$pids 2>/dev/null || true; \
	fi

health: ## curl GET /api/v1/health
	@curl -sf "$(BASE_URL)/api/v1/health" | python3 -m json.tool

# ---------------------------------------------------------------------------
# Frontend
# ---------------------------------------------------------------------------

run: run-frontend ## Alias for run-frontend

run-frontend: ## flutter run -d $(DEVICE) (backend should already be up)
	cd "$(FRONTEND)" && flutter run -d "$(DEVICE)"

build: build-frontend ## Alias for build-frontend

build-frontend: ## flutter build $(DEVICE)
	cd "$(FRONTEND)" && flutter build "$(DEVICE)"

pub-get: setup-frontend ## Alias for setup-frontend

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test: test-backend test-frontend ## Backend pytest + frontend widget tests

test-backend: ## pytest in backend/
	@if [[ ! -x "$(VENV_PYTHON)" ]]; then \
		echo "Missing $(VENV_PYTHON) — run: make setup-backend" >&2; \
		exit 1; \
	fi
	cd "$(BACKEND)" && .venv/bin/pytest

test-frontend: ## flutter test (widget / unit)
	cd "$(FRONTEND)" && flutter test

test-integration: ## Integration E2E via scripts/run_integration_tests.sh [SUITE=file]
	@if [[ -n "$(SUITE)" ]]; then \
		"$(ROOT)/scripts/run_integration_tests.sh" "$(SUITE)"; \
	else \
		"$(ROOT)/scripts/run_integration_tests.sh"; \
	fi

analyze: ## flutter analyze
	cd "$(FRONTEND)" && flutter analyze

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

clean: ## Remove Flutter build artifacts (keeps backend/.venv)
	cd "$(FRONTEND)" && flutter clean
	@echo "Kept backend/.venv — remove manually if needed: rm -rf backend/.venv"
