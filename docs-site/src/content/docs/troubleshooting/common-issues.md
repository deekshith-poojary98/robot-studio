---
title: Troubleshooting
description: Fix common Robot Studio issues — backend offline, empty runs, missing imports, and more.
---

## How to report a bug

Private beta: open an issue on [GitHub](https://github.com/deekshith-poojary98/robot-studio/issues). Include OS, what you did, and what you expected. Logs live under `~/.robot-studio/logs/` if you need to attach them.

## Linux: `Exec format error` when running `./robot_studio`

The zip CPU does not match the machine. Run `uname -m`:

- `x86_64` → download **`Robot-Studio-*-linux-x64.zip`**
- `aarch64` / `arm64` → download **`Robot-Studio-*-linux-arm64.zip`** (Apple Silicon / ARM VMs)

Then unzip and either double-click `robot-studio.desktop` (Allow Launching), run `./robot_studio`, or once run `./install-desktop-launcher.sh` for the app menu.

## Linux: Could not create environment / `python3-venv`

Ubuntu/Debian ship Python without the `venv` module. Install it once, then create the environment again:

```bash
sudo apt install python3-venv
# or, if the dialog names a version (e.g. 3.14):
sudo apt install python3.14-venv
```

Confirm with `python3 -m venv --help`, then in Robot Studio use **Create Environment** again. This is host setup (like installing Python on Windows) — not part of the app zip.

## Linux: Could not install Robot Framework / `No module named pip`

Same class of Ubuntu split: Python is present but **pip** is not. Install once:

```bash
sudo apt install python3-pip python3-venv
# or versioned, e.g.:
sudo apt install python3.14-pip python3.14-venv
```

Delete the half-created env under the project’s `.robotstudio/environments/` if Create failed mid-way, then **Create Environment** again.

Newer builds also try `ensurepip` inside the new venv and show this apt hint when pip still cannot start.
## Problems: can't open `robot_parsing_worker.py` / Missing library `BuiltIn`

The language tools run a small worker script from the packaged backend. Older Linux/Windows/macOS zips omitted that file from the sidecar freeze, so Problems shows a missing path under `backend/_internal/.../robot_parsing_worker.py` and often `Missing library 'BuiltIn'`.

**Fix:** download a build that includes the worker in PyInstaller datas (re-run **Actions → Package Desktop** after that fix), replace the unzipped app, and reopen the project. Confirm the file exists:

```bash
ls backend/_internal/robot_studio/infrastructure/language/robot_parsing_worker.py
```

## Windows: missing `MSVCP140.dll` / `VCRUNTIME140.dll`

The zip is fine — the VM is missing the Microsoft C++ runtime Flutter needs.

1. Download and install **[Visual C++ Redistributable (x64)](https://aka.ms/vc14/vc_redist.x64.exe)** (`vc_redist.x64.exe`).
2. Restart if Windows asks, then double-click `RobotStudio.exe` again.

You only need this once per machine. Many full Windows installs already have it; clean VMs often do not.

## Windows: env toast takes ~1–2 minutes / APIs time out

Usually the sidecar stalled after open: console subprocesses (`git`, etc.) spawned without `CREATE_NO_WINDOW` from the packaged GUI app can freeze the asyncio loop. Fixed in current builds — re-run **Actions → Package Desktop**.

**Still says “Python is not installed” with Store / aliases:** App execution aliases only enable install-manager stubs. Install a runtime with `py install 3` (or python.org + Add to PATH), add `%LOCALAPPDATA%\Python\bin` to PATH if prompted, confirm `py list`, restart Robot Studio.

## Windows: Could not detect Python / Python is not installed

Robot Studio needs a **real Python 3 runtime** to create project environments. Enabling **App execution aliases** only turns on the install-manager stubs (`python.exe` / `py.exe` shortcuts) — that is **not** the same as having Python installed.

1. In Command Prompt on the VM run: `py install 3`  
   **or** install from [python.org](https://www.python.org/downloads/) with **Add python.exe to PATH**
2. Confirm with `py list` or `where python` (should show a real path, not only WindowsApps stubs)
3. Restart Robot Studio
4. Or in Create Environment use **Browse…** and pick `python.exe` yourself

Logs: `%USERPROFILE%\.robot-studio\logs\` (`frontend-*.log` / `backend-*.log`).

## Windows: Browse… closes the app (New Project / Open)

Folder picker used an older `file_picker` build that could kill the process on some Windows hosts (especially **ARM64 / VMware**) via a COM conflict — no Dart error, just “Lost connection to device”.

**Workaround:** type or paste the folder path instead of Browse.

**Fix:** update to a build with `file_picker` ≥ 9.2.3 (isolate-safe Windows directory picker), then `flutter pub get` and rebuild.

## Status bar says BACKEND UNAVAILABLE

The UI cannot reach the local API.

**Packaged app:** quit Robot Studio fully and reopen it. The sidecar should start with the app.

**From source:** ensure `make backend` is running and `make health` returns OK on port `8765` (or your overridden port).

Health is rechecked automatically; once the backend is back, the shell recovers without restarting the UI.

## Cannot open a project on Desktop / Documents (macOS)

If open fails with **Permission denied** (or a bare Internal Server Error), the backend process likely lacks macOS folder access. Start it from **Terminal** with `make backend` — not from a restricted/agent shell — then reopen the project in the app.

## Create Project / Manage Environments… is disabled

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
- Insights / Search / **Go → Find Symbol in Project…** stay incomplete until indexing finishes

Large rebuilds can feel slower after the first few thousand files if the database is growing —
Robot Studio keeps symbol writes in one transaction per file and indexes reference lookups so
per-file cleanup stays fast as the store fills.

## Completions or go-to-definition feel wrong

- Wait for indexing to finish after opening a large project.
- Confirm the active environment matches the libraries your suite imports.
- Trigger a full index rebuild if results look stale.

Relaunch only runs an **incremental** pass (mtime skip). If the footer shows **Indexing workspace…** for a long time with no `N/M` progress after a recent open, hot-restart once — a late open event used to leave that label stuck after indexing had already finished.

## Live Output only appears when the run finishes

Robot Framework was previously started with buffered stdout when piped, so console lines flushed at process exit. Robot Studio now starts Robot with unbuffered Python (`-u` / `PYTHONUNBUFFERED`). Hot-restart the app and run again — lines should appear during the run in **Live Output**.

Long project runs (thousands of tests) rewrite `output.xml` continuously and stream a lot of console output. Robot Studio now:

- Ignores `.robotstudio/reports` watcher noise during the run
- Batches / caps the execution console
- Keeps Save from waiting on Git refresh

If the UI still feels sticky, leave the **Tests** / Execution view while the run finishes, or stop the run before heavy editing. Reports still appear when the run completes.

## Git shows the wrong repository

Git is scoped to the active project folder. Open the project that actually contains the `.git` directory you intend — Robot Studio will not attach to a parent monorepo by surprise.

## Find in Files misses a file type

Add the suffix under **Settings → Search → Content Search Extensions** — see [Settings](/reference/settings/).

## Still stuck?

Open the failure dialog’s **Show details** only when you need the raw exception for a bug report. The primary message should already say what happened and how to fix it.
