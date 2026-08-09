---
title: Troubleshooting
description: Fix common Robot Studio issues — backend offline, empty runs, missing imports, and more.
---

## Status bar says BACKEND UNAVAILABLE

The UI cannot reach the local API.

**Packaged app:** quit Robot Studio fully and reopen it. The sidecar should start with the app.

**From source:** ensure `make backend` is running and `make health` returns OK on port `8765` (or your overridden port).

Health is rechecked automatically; once the backend is back, the shell recovers without restarting the UI.

## Create Project / Manage Environments is disabled

Open or create a **project** first. Those actions stay gated on the welcome screen until a project is active.

## Tests will not run

1. Confirm a project is open.
2. Confirm an environment is **activated** and includes Robot Framework.
3. Check Problems / Robot Doctor for missing imports that would fail collection.
4. For huge suites, look for a confirmation dialog you may have dismissed.

## Index rebuild on a huge project

**Rebuild Index** starts in the background and returns immediately. Watch the footer status bar for `Indexing… N/M`.

For projects with thousands of files:

- Leave the rebuild running — do not treat a long wait as a failure
- Indexing parses files with multiple workers (capped) while writing the symbol store on one path
- Prefer editing after the status bar shows the index is synchronized
- Insights / Search / Go to Symbol stay incomplete until indexing finishes

Large rebuilds can feel slower after the first few thousand files if the database is growing —
Robot Studio keeps symbol writes in one transaction per file and indexes reference lookups so
per-file cleanup stays fast as the store fills.

## Completions or go-to-definition feel wrong

- Wait for indexing to finish after opening a large project.
- Confirm the active environment matches the libraries your suite imports.
- Trigger a full index rebuild if results look stale.

Relaunch only runs an **incremental** pass (mtime skip). If every open feels like a full rebuild, use **Rebuild Index** once, then relaunch again — later opens should settle quickly when files are unchanged.

## UI freezes while a huge run is in progress

Long project runs (thousands of tests) rewrite `output.xml` continuously and stream a lot of console output. Robot Studio now:

- Ignores `.robotstudio/reports` watcher noise during the run
- Batches / caps the execution console
- Keeps Save from waiting on Git refresh

If the UI still feels sticky, hide the Execution panel while the run finishes, or stop the run before heavy editing. Reports still appear when the run completes.

## Git shows the wrong repository

Git is scoped to the active project folder. Open the project that actually contains the `.git` directory you intend — Robot Studio will not attach to a parent monorepo by surprise.

## Find in Files misses a file type

Add the extension to `ROBOT_STUDIO_CONTENT_SEARCH_EXTENSIONS` — see [Settings reference](/reference/settings/).

## Still stuck?

Open the failure dialog’s **Show details** only when you need the raw exception for a bug report. The primary message should already say what happened and how to fix it.
