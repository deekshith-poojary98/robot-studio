---
title: Settings
description: Configure Robot Studio from the Settings screen — the primary place for user preferences.
---

Open **Settings** with the gear at the bottom of the activity bar, **File → Settings…**, or `⌘,` / `Ctrl+,`.

Settings are stored in `~/.robot-studio/settings.json`. Use **Save** to apply changes. **Restore Defaults** resets every category; **Discard** drops an unsaved draft.

## Editor

| Setting | Default | What it does |
|---------|---------|----------------|
| **Auto Save** | Off | Saves changed files about two seconds after you stop typing |
| **Save Before Run** | On | Writes pending edits before a run starts |
| **Word Wrap** | On | Wraps long lines in the editor |
| **Insert Spaces** | On | Indent with spaces instead of tab characters |
| **Tab Width** | `4` | Spaces per indent level |
| **Font Size** | `13` | Editor font size |
| **Font Family** | `Menlo` | Monospace fonts **installed on this computer**. Robot Studio does not ship extra typefaces and does not keep a hand-picked list beyond the Menlo default. Install a font in the OS (Font Book on macOS), relaunch if it does not appear, pick it here, then Save. |
| **Python Member Checks** | Off | Warn on unknown Python attributes (`obj.wrong`) and unexpected call keywords (`func(nope=…)`). Useful on typed code; can be noisy when Jedi cannot infer types (Path variables, Pydantic models, AST walkers). |

## Execution

| Setting | Default | What it does |
|---------|---------|----------------|
| **Large Run Threshold** | `100` | Ask for confirmation before project-wide runs larger than this many tests |
| **Reveal Execution On Run** | On | Bring the execution monitor forward when a run starts |
| **Auto Open Report On Failure** | Off | Open Reports when tests failed. Empty selection (**NO TESTS**) does not count as a failure. |
| **Stop Confirmation** | On | Confirm before stopping a running suite |

## Search

| Setting | Default | What it does |
|---------|---------|----------------|
| **Content Search Extensions** | `.robot`, `.resource`, `.py`, `.yaml`, `.yml`, `.txt`, `.md`, `.json`, `.tsv`, `.csv` | File suffixes scanned by Find in Files |
| **Ignore Patterns** | `.git`, `.venv`, `venv`, `node_modules`, `__pycache__`, `.robotstudio`, `.DS_Store` | Paths skipped by Find in Files |

## Appearance

| Setting | Default | What it does |
|---------|---------|----------------|
| **Theme** | Dark | Dark, Light, or System |
| **Accent** | Teal (Default) | Accent colour for chrome |
| **Restore Last Project** | On | Reopen the last project or workspace when Robot Studio starts |

## Advanced: backend environment variables

These `ROBOT_STUDIO_*` variables configure the **local backend process**. Day-to-day preferences belong in **Settings** above.

| Variable | Default | Meaning |
|----------|---------|---------|
| `ROBOT_STUDIO_HOST` | `127.0.0.1` | Bind address |
| `ROBOT_STUDIO_PORT` | `8765` | HTTP / WebSocket port |
| `ROBOT_STUDIO_DATA_DIR` | `~/.robot-studio` | SQLite DB, plugins, local data, logs |
| `ROBOT_STUDIO_DEBUG` | `false` | Debug mode |

`ROBOT_STUDIO_LARGE_RUN_THRESHOLD` and `ROBOT_STUDIO_CONTENT_SEARCH_EXTENSIONS` exist as **backend fallbacks** when settings are not loaded. Prefer **Settings → Execution / Search** for normal use.

Database path: `{data_dir}/robot-studio.db`. Contributor packaging notes live in the repository README.
