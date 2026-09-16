# Robot Studio 1.1.0

**Date:** 2026-09-16  
**Kind:** Packaged release via [GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases). Zip only (same as 1.0.0).  
**Version:** `1.1.0` (matches backend `robot_studio.__version__`; GitHub tag `v1.1.0`).

Desktop IDE for [Robot Framework](https://robotframework.org/). This release ships **Impact Analysis** — the first post-beta semantic RF workflow.

**User guide:** https://deekshith-poojary98.github.io/robot-studio/  
**Impact workflow:** https://deekshith-poojary98.github.io/robot-studio/workflows/impact-analysis/

---

## Get the build

Download the zip for your OS **and CPU** from **[GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases)** (tag **`v1.1.0`**).

| Platform | What to open | Notes |
|----------|----------------|-------|
| **macOS** | `Robot Studio.app` | Unzip, double-click. Gatekeeper may require **Open Anyway**. |
| **Windows** | `RobotStudio/RobotStudio.exe` | Keep the unzipped folder together. Clean VMs may need [VC++ Redistributable (x64)](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist). |
| **Linux x64** | `RobotStudio/robot_studio` | Run `./robot_studio`, or use the `.desktop` launcher. |
| **Linux arm64** | `RobotStudio/robot_studio` | Use the `linux-arm64` zip (`uname -m` → `aarch64`). |

Maintainers: push tag **`v1.1.0`** to run **Actions → Package Desktop** and attach zips (e.g. `Robot-Studio-1.1.0-macos.zip`).

App data: `~/.robot-studio`. Project Studio files: `.robotstudio/` inside the project.

---

## What’s new in 1.1.0

### Impact Analysis (flagship)

Answer **which tests should I re-run?** after changing a shared keyword, resource, or variable — not only where the name appears.

1. Place the caret on a **keyword**, **resource import path**, or **variable** (or select it in the outline).
2. Run **Impact Analysis** — **Go → Impact Analysis**, or Command Palette → **Impact Analysis**.
3. The right-hand **Impact** panel lists **Affected** (certain) and **Uncertain** (low-confidence) tests, with Direct / Transitive / Import / Variable and a short **why**.
4. Click a row to jump to that test. Optionally **Run Impact Set** (panel button, **Go → Run Impact Set**, or palette) to re-run only the **certain** hits through the normal run pipeline (active run config, save-before-run, Stop, reports, large-run confirm).
5. While the panel is open, results **refresh** after the analysis index updates (for example after you save related files).

Requires an open project with a built analysis graph (wait for indexing / rebuild if the panel says the graph is empty).

**Guide:** [Impact Analysis](https://deekshith-poojary98.github.io/robot-studio/workflows/impact-analysis/)

### Still from 1.0.0

Everything in the 1.0.0 beta (editor intelligence, environments, run configs, reports, Git, Doctor, Search, …) remains. See the 1.0.0 section below for the full list.

---

## Known limits

- Impact is graph-based: dynamic / unbound usages stay in **Uncertain** (or missing) — never silently treated as certain.
- Editor context menu entry for Impact is not required for this cut (Go menu + palette).
- Safe Rename, debugger, AI, flaky analysis, and notarized installers are **not** in 1.1.0.
- macOS Gatekeeper may still warn (ad-hoc signed).

---

## Feedback

File bugs on [GitHub Issues](https://github.com/deekshith-poojary98/robot-studio/issues). Include OS, steps, and expected result. Logs: `~/.robot-studio/logs/`.

---

# Robot Studio 1.0.0 — Beta (previous)

**Date:** 2026-09-12  
**Kind:** Packaged beta via [GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases). Not an App Store / installer release (zip only).  
**Version:** `1.0.0` (matches backend `robot_studio.__version__`; GitHub tag `v1.0.0`).

Desktop IDE for [Robot Framework](https://robotframework.org/). Open a project, pick an environment, write tests, run them, and read reports without leaving the app.

**User guide:** https://deekshith-poojary98.github.io/robot-studio/

---

## Get the build (1.0.0)

Download the zip for your OS **and CPU** from **[GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases)** (tag **`v1.0.0`**).

| Platform | What to open | Notes |
|----------|----------------|-------|
| **macOS** | `Robot Studio.app` | Unzip, double-click. You can drag it into Applications yourself. First launch may be blocked by Gatekeeper — **System Settings → Privacy & Security → Open Anyway**. |
| **Windows** | `RobotStudio/RobotStudio.exe` | Unzip the folder, double-click the exe. Keep the folder together. Clean VMs need the [VC++ Redistributable (x64)](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist) if you see missing `MSVCP140.dll` / `VCRUNTIME140*.dll`. |
| **Linux x64** | `RobotStudio/robot_studio` | Unzip, run `./robot_studio`, or double-click `robot-studio.desktop` (first time: **Allow Launching**). Optional: `./install-desktop-launcher.sh` for the app menu; `./uninstall.sh` (`--purge` also deletes `~/.robot-studio`). |
| **Linux arm64** | `RobotStudio/robot_studio` | Same as x64. Use the `linux-arm64` zip on Apple Silicon / ARM VMs (`uname -m` → `aarch64`). An x64 zip shows `Exec format error`. |

Maintainers: all zips are produced by **GitHub Actions → Package Desktop** (each OS/arch builds on its own runner; no cross-compile). Push a `v*` tag to attach zips to that Release. Zip filenames use the backend version (e.g. `Robot-Studio-1.0.0-macos.zip`).

There is **no installer** (no `.dmg` / `.msi` / `.deb`). Do not start Python by hand — the backend is inside the app. Quit the app to stop it.

App data: `~/.robot-studio`. Project Studio files: `.robotstudio/` inside the project.

---

## What’s in 1.0.0

- **Projects** — New / Open / Recent. Any Robot folder; new projects get `tests/`, `resources/`, `variables/`.
- **Environments & packages** — Create, import, clone, or activate a venv. In Environment Manager, the active environment shows a green, disabled **Active** button; choose **Activate** on another row to switch (flat dense list, no cards). Search PyPI by name (**exact → prefix → substring**; no fuzzy matching). Install / update / uninstall, import/export requirements. Status bar shows **ROBOT** and **PYTHON** from the active environment.
- **Editor** — Multi-tab Robot + Python. Completions (named `arg=` after a keyword, including Setup / Teardown / Template), hover, signature help, go to definition, find references, rename symbol, find/replace, outline, breadcrumbs, live diagnostics. **Problems** can offer a Fix (install a missing package or add a `Library` import). Python intelligence uses the active environment (Jedi). Embedded-argument keywords such as `Login with ${type} credential` match calls like `Login with valid credential`. With no open tab, a centered **Start** / **Recent** page (last 3 files) offers **Open File…**, **Show Explorer** / **Hide Explorer**, search, run, and environments.
- **Toggle Side Bar** — `⌘B` / `Ctrl+B`, **View → Toggle Side Bar**, or click the logo mark at the top of the activity bar.
- **Run** — Toolbar **Run / Project / Stop**, Tests tree, gutter play / **Run Test at Cursor**, run configurations (tags, variables, optional env pin). In **Manage Configurations…**, the active config shows a green, disabled **In Use** button; choose **Use** on another row to switch. Live output and **Now Running** (suite / test / keyword + elapsed). **Stop** confirms, then the toolbar shows **Stopping** until Robot exits. The **Last:** chip is **Passed**, **Failed**, **No tests**, **Error**, **Cancelled**, or **Aborted**. Failed Tests with jump-to-source and re-run. Parent `__init__.robot` Suite Setup still runs for file and single-test runs.
- **Reports & Insights** — Run history, HTML log/report, on-demand **Generate ReportLens** (from `output.xml`, opens in the browser). **Settings → Execution → Report Retention Days** auto-deletes old run folders (`0` = keep forever; deleted runs also leave Insights analytics). Insights triage from the same history. A keywords-only file or a tag that matches nothing is **No tests**, not Failed.
- **Git** — Status, commit, branches, remotes, history, diff. Always the open project, not a parent repo.
- **Doctor, Search, Libraries, Terminal, Settings** — Project health, Find in Files / Find Symbol, library docs, bottom terminal, theme / font / execution prefs. **Command Palette** (`⌘⇧P` / `Ctrl+Shift+P`) for commands, files, and symbols.
- **Backend port** — Packaged app prefers `8765`; if that port is taken, it allocates a free nearby port and stores it in `~/.robot-studio/backend.port`.

---

## Known limits (1.0.0)

- Beta — expect bugs. Please report them (below).
- macOS Gatekeeper may warn (ad-hoc signed, not notarized). Open anyway from System Settings if needed.
- Plugins stay in the product but are hidden from the activity bar for this beta.
- Git has no stash, merge/rebase, conflict UI, or discard/restore.
- No AI, debugger, impact analysis, or flaky-test product in this release.

---

## Feedback (1.0.0)

File bugs and requests on [GitHub Issues](https://github.com/deekshith-poojary98/robot-studio/issues).

Include OS, what you did, and what you expected. Logs (if useful) are under `~/.robot-studio/logs/`.
