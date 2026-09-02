---
title: Troubleshooting
description: Fix common Robot Studio issues — backend offline, empty runs, missing imports, and more.
---

## How to report a bug

Private beta: open an issue on [GitHub](https://github.com/deekshith-poojary98/robot-studio/issues). Include OS, what you did, and what you expected. Logs live under `~/.robot-studio/logs/` if you need to attach them (`frontend-*.log` and `backend-*.log`). Backend logs include each API call (method, path, status, duration), execution start/stop/finish, and unexpected crashes with a stack trace.

## macOS: “Robot Studio” Not Opened after unzip

Gatekeeper blocks the beta zip because the app is not notarized. That is expected — not a corrupt download.

1. Open **System Settings → Privacy & Security**.
2. Under **Security**, find *“Robot Studio” was blocked to protect your Mac.*
3. Click **Open Anyway**, then confirm **Open**.

If that line is not there yet, double-click the app once more from Finder (dismiss **Done** if needed), then check Privacy & Security again. You only do this once per download. Also covered in [Install](/getting-started/install/#macos-app-blocked-after-unzip).

## Linux: `Exec format error` when running `./robot_studio`

The zip CPU does not match the machine. Run `uname -m`:

- `x86_64` → download **`Robot-Studio-*-linux-x64.zip`**
- `aarch64` / `arm64` → download **`Robot-Studio-*-linux-arm64.zip`** (Apple Silicon / ARM VMs)

Then unzip and either double-click `robot-studio.desktop` (Allow Launching), run `./robot_studio`, or once run `./install-desktop-launcher.sh` for the app menu. To remove the menu entry: `./uninstall.sh` (`--purge` also deletes `~/.robot-studio`).

## Linux: Could not create environment / `python3-venv`

Ubuntu/Debian ship Python without the `venv` module. Install it once, then create the environment again:

```bash
sudo apt install python3-venv
# or, if the dialog names a version (e.g. 3.14):
sudo apt install python3.14-venv
```

Confirm with `python3 -m venv --help`, then in Robot Studio use **Create Environment** again. This is host setup (like installing Python on Windows) — not part of the app zip.

## Linux: Initialize Git → Internal Server Error / Git is not installed

Source Control calls the system `git` binary. Ubuntu VMs often do not have it:

```bash
sudo apt install git
git --version
```

Restart Robot Studio, then **Initialize Git** again. Older zips returned HTTP 500 and said “Install Git for Windows” even on Linux — current builds show the apt hint instead.

## Linux: Could not install Robot Framework / `No module named pip`

Same class of Ubuntu split: Python is present but **pip** is not. Install once:

```bash
sudo apt install python3-pip python3-venv
# or versioned, e.g.:
sudo apt install python3.14-pip python3.14-venv
```

Delete the half-created env under the project’s `.robotstudio/environments/` if Create failed mid-way, then **Create Environment** again.

Newer builds also try `ensurepip` inside the new venv and show this apt hint when pip still cannot start.

## Linux: `externally-managed-environment` / PEP 668

Pip ran against **system** Python (`/usr/bin/python3`) instead of the project venv. Ubuntu blocks that on purpose.

Current builds keep the venv’s `bin/python` wrapper (they no longer follow the symlink to `/usr/bin/python3`). Update Robot Studio, delete any half-created env under `.robotstudio/environments/`, then Create Environment again.

## Linux: pip SSL / `ssl module is not available`

The selected Python cannot do HTTPS, so PyPI installs fail. Ubuntu’s minimal `python3` often needs the full stdlib:

```bash
sudo apt install python3-full ca-certificates
# If python3 still fails, install the versioned full package (Ubuntu 26.04):
sudo apt install python3.14-full ca-certificates
python3 -c "import ssl; print(ssl.OPENSSL_VERSION)"
python3.14 -c "import ssl; print(ssl.OPENSSL_VERSION)"
```

If `python3-full` is already installed but `import ssl` still fails **in a terminal**, `/usr/bin/python3` may point at a minimal build — use **Browse** in Create Environment and pick `/usr/bin/python3.14` (or whichever path passes the check above).

If SSL works in a terminal but Robot Studio still reports “cannot import ssl”, you are likely on an older Linux zip where the packaged backend inherited PyInstaller's `LD_LIBRARY_PATH` into child Python processes. Update to a build that clears that when spawning host Python, or test on Windows/macOS for beta.

Delete the half-created env under `.robotstudio/environments/`, then Create Environment again.

## Linux: Problems says `No module named robot` / Missing `BuiltIn`

The project venv can have Robot Framework (`pip list` inside `.robotstudio/environments/default` shows `robotframework`) while Problems and **Run** still use **system** Python (`/usr/bin/python3.14: No module named robot`). On Linux the venv `bin/python` is a symlink; older zips followed it and ran the OS interpreter.

The run timer can also keep going after that error (the abort was ignored in the UI).

**Fix:** update Robot Studio to a build that keeps the venv wrapper for parse, pip, and run. Your existing environments are fine — just reopen the project and Run again.

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

Usually the sidecar stalled after open: console subprocesses (`git`, Python probes, etc.) spawned from the packaged GUI app can freeze the asyncio loop when they allocate a console or when indexing + git/env probes compete for the small default thread pool. Current builds use `CREATE_NO_WINDOW`, a larger blocking thread pool, and non-blocking file-watcher setup — re-run **Actions → Package Desktop**.

If the status bar flips to **BACKEND UNAVAILABLE** after ~30s timeouts, also check for a **stale sidecar**: quit Robot Studio, open Task Manager, end any `robot-studio-backend.exe`, delete `%USERPROFILE%\.robot-studio\backend.pid` if present, then relaunch. Current builds also **restart the owned sidecar** automatically after repeated failed health checks (wait up to a minute between attempts).

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

## macOS: Browse shows ENTITLEMENT_NOT_FOUND

Robot Studio runs **outside** the App Sandbox (so Terminal and Robot runs can reach your projects). Older builds used a plugin that refused to open the folder picker without sandbox entitlements.

**Fix:** use a current build — Browse / Open Project use Studio’s own macOS panels. Until you update, type or paste the path into the dialog field.

## Status bar says BACKEND UNAVAILABLE

The UI cannot reach the local API.

**Packaged app:** quit Robot Studio fully and reopen it. The sidecar should start with the app.

**From source:** ensure `make backend` is running and `make health` returns OK on port `8765` (or your overridden port).

Health is rechecked automatically (about every 2 seconds while offline). Once the backend is back, the shell reconnects live streams and **re-opens the project you still had on screen** (backend memory is empty after a restart). If a file open fails with “Open a workspace before accessing files” on an older build, use **Open Project** again or restart the UI.

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

## Python: no completions, hover, or Problems in a `.py` file

Python intelligence resolves against the **active environment**, so it needs one selected.

- Activate an environment (**Manage Environments…**), then reopen the file.
- If completions cover the stdlib but miss a package you installed, the package landed in a different environment than the active one — check with **Packages**.
- Symbols starting with `_` are hidden until you type the leading underscore.
- While a file has a syntax error, only parse errors are listed. Undefined names, unused imports, and missing-package warnings come back once the file parses.
- `import pandas` (or any other third-party package) warns when that package is not installed in the **active** environment. `from pandas import NotARealClass` warns when the package exists but that name does not. Use **Fix** on the Problems row, or **Packages → Install**, or wrap optional imports in `try` / `except ImportError`.

## Python: Format Document does nothing

Robot Studio does not bundle a Python formatter — it uses the one in your environment so the result matches your project config and CI.

**Fix:** install `ruff` or `black` into the active environment (**Packages → Install**). With neither present, Format Document only trims trailing whitespace.

## Python: Rename Symbol is unavailable

Rename works on Python files with the caret on a symbol, and on Robot files with the caret on a user keyword (**Edit → Rename Symbol…**, or the command palette). BuiltIn keywords cannot be renamed. If it reports that the name is invalid, the new text is not a valid identifier (Python) or keyword name (Robot). Renaming rewrites usages across the project, including files that are not open, so review the changes before committing.

## Live Output only appears when the run finishes

Robot Framework was previously started with buffered stdout when piped, so console lines flushed at process exit. Robot Studio now starts Robot with unbuffered Python (`-u` / `PYTHONUNBUFFERED`). Hot-restart the app and run again — lines should appear during the run in **Live Output**.

Long project runs (thousands of tests) rewrite `output.xml` continuously and stream a lot of console output. Robot Studio now:

- Ignores `.robotstudio/reports` watcher noise during the run
- Batches / caps the execution console
- Keeps Save from waiting on Git refresh

If the UI still feels sticky, leave the **Tests** / Execution view while the run finishes, or stop the run before heavy editing. Reports still appear when the run completes.

## Insights shows unavailable, then works on the second open

On very large projects the first Insights load can take longer than a short request window (cold index / first per-file stats). Robot Studio now waits longer and shows a clear failure with **Refresh**. Open Insights again or tap **Refresh** — the second load is usually fast once caches are warm.

## Git shows the wrong repository

Git is scoped to the active project folder. Open the project that actually contains the `.git` directory you intend — Robot Studio will not attach to a parent monorepo by surprise.

## Find in Files misses a file type

Add the suffix under **Settings → Search → Content Search Extensions** — see [Settings](/reference/settings/).

## Single file fails, whole project passes

If every test in one file dies with something like **Non-existing index or alias 'api'**, a parent `__init__.robot` Suite Setup (often `Create Session`) is not running.

That happens when Robot is started on the leaf file instead of the folder that owns `__init__.robot`. Robot Studio now starts at that parent and filters with `--suite`, so **Run File** / a single test should match **Run Project** for those setups. Update to a build with that behavior, then run the file again.

If it still fails, open `tests/__init__.robot` (or the nearest parent init) and confirm Suite Setup creates the session or resource the tests use.

## Still stuck?

Open the failure dialog’s **Show details** only when you need the raw exception for a bug report. The primary message should already say what happened and how to fix it.
