---
title: What is Robot Studio?
description: A short orientation to Robot Studio and who it is for.
---

**Robot Studio** is a desktop IDE made for [Robot Framework](https://robotframework.org/) development.

It is not a generic code editor with a Robot plugin bolted on. The product is built around the loop you already live in: open a project, activate a Python environment, write `.robot` / `.resource` files, run tests, fix failures, and inspect reports.

## Who it is for

- Teams writing acceptance and automation tests in Robot Framework
- Engineers who want project + environment + runner + reports in one desktop app
- People who prefer a focused Robot workspace over wiring up a general IDE from scratch

## What you get

| Area | In practice |
|------|-------------|
| **Projects** | Open any Robot folder, or create a new project with `tests/`, `resources/`, and `variables/` |
| **Environments & packages** | Create, import, or activate a venv; install libraries from PyPI via **Packages** |
| **Editor** | Multi-tab Robot editing with completions, diagnostics, go to definition, and outline |
| **Run** | Toolbar **Run** / **Project** / **Stop**, **Tests** tree, run configurations (tags, variables), live logs |
| **Reports** | Browse run history and open `report.html` / `log.html`; **Failed Tests** with Jump to Source |
| **Insights** | Triage run health and jump into failures, source, or Reports |
| **Robot Doctor** | Structural project health (circular imports, duplicates, unused assets) |
| **Libraries** | Browse BuiltIn and imported library keywords and docs |
| **Search** | Find in Files and Find Symbol in Project |
| **Git** | Status, stage, commit, branches, and diff scoped to the active project |
| **Terminal** | Bottom-panel shell rooted at the project folder |
| **Settings** | Editor, execution, search, and appearance preferences |

## How the app is shaped

Robot Studio pairs a **Flutter desktop** UI with a local **Python** backend. When you use the packaged app, the backend starts with the app. You work on your machine; nothing in the normal loop requires a cloud account.

App data (database, Settings, logs) lives under `~/.robot-studio`. Project-specific Studio state lives under `.robotstudio/` inside the project.

## Private beta

This is a **private beta**. Expect bugs; please file them on [GitHub Issues](https://github.com/deekshith-poojary98/robot-studio/issues). Packaged builds are zip-only (no installer). Longer-term product direction (not shipped features) is sketched on the [Roadmap](/getting-started/roadmap/).

## Next step

→ [Install Robot Studio](/getting-started/install/)
