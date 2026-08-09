---
title: What is Robot Studio?
description: A short orientation to Robot Studio and who it is for.
---

**Robot Studio** is a cross-platform desktop IDE made for [Robot Framework](https://robotframework.org/) development.

It is not a generic code editor with a Robot plugin bolted on. The product is built around the loop you already live in: open a project, activate a Python environment, write `.robot` / `.resource` files, run tests, fix failures, and inspect reports.

## Who it is for

- Teams writing acceptance and automation tests in Robot Framework
- Engineers who want project + environment + runner + reports in one desktop app
- People who prefer a focused Robot workspace over wiring up a general IDE from scratch

## What you get

| Area | In practice |
|------|-------------|
| **Projects** | Open any Robot folder, or create a new project with `tests/`, `resources/`, and `variables/` |
| **Environments** | Create, import, or activate a venv; install packages from PyPI |
| **Editor** | Multi-tab Robot editing with completions, diagnostics, go to definition, and outline |
| **Execution** | Run a file, suite, selection, or whole project with live logs |
| **Reports** | Browse run history and open `report.html` / `log.html` |
| **Git** | Status, stage, commit, branches, and diff scoped to the active project |

## How the app is shaped

Robot Studio pairs a **Flutter desktop** UI with a local **Python** backend. When you use the packaged app, the backend starts with the app. You work on your machine; nothing in the normal loop requires a cloud account.

Data for the app (database, plugins, preferences) lives under `~/.robot-studio`. Project-specific Studio state lives under `.robotstudio/` inside the project.

## Next step

→ [Install Robot Studio](/getting-started/install/)
