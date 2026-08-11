---
title: Run, stop & re-run
description: How test execution works — toolbar runs, Tests tree, confirmation thresholds, and stop.
---

## Ways to run

| Action | Typical use |
|--------|-------------|
| **Run** (toolbar) / **Run → Run File** (`F5`) | Current open `.robot` suite in the editor — not a text selection |
| **Project** (toolbar) / **Run → Run Project** | Entire project |
| **Tests** (activity bar) | One test, one suite, all, current file, or failed |
| **Re-run Test** | A single failure from the last run (**Failed Tests**) |

## Run configurations

The toolbar selector immediately before **Run / Project / Stop** chooses a **run configuration** — a named execution context for the next run.

| Selector | Meaning |
|----------|---------|
| **Default** | No extra tags, variables, or environment pin. Uses the active toolbar environment. |
| **Smoke - Staging** (example) | Applies that configuration’s include/exclude tags, variables, variable files, and optional environment pin |

**Run** and **Project** keep their usual meaning (current file vs whole project). The selector only supplies execution context. Tests-tree **Run**, **Run Failed**, and **Re-run Test** use the same selected configuration.

Selecting a configuration does **not** change the toolbar environment. Packages, Libraries, and language intelligence stay on the active environment. A configuration may pin an environment for **that run only**; the environment actually used is recorded on the run in Reports.

### Create and manage

From the selector: **New Configuration…** or **Manage Configurations…** (dialogs — not a new sidebar or Settings page). In Manage, **Duplicate** is a first-class action so you can clone **Smoke - Dev** into **Smoke - Staging** and change a few fields.

Configurations are stored with the project at `.robotstudio/run-configurations.json` (same Studio metadata folder as environments and reports).

Advanced Robot arguments are an escape hatch: one argv token per row, not a shell command. Studio-owned options such as `--outputdir` and `--listener` are rejected.

Logs stream into **Live Output** while a run is in progress (Robot is started with unbuffered stdout so lines are not held until the process exits). The **Now Running** panel on the right shows the live call stack — suite, test, and current keyword — plus elapsed time while the run is active. After the run ends, it keeps the last location until the next start.

**Stop** cancels the run (with a confirmation that shows what is currently executing). Output so far is kept; the HTML report may be incomplete.

## Large runs

If a project-wide run would execute more than the configured threshold (default **100** tests), Robot Studio asks for confirmation. Change the threshold in **Settings → Execution → Large Run Threshold**.

## After you stop or finish

- Finishing a run does not yank you into another view; use the **View Report** toast when you want results.
- **Failed Tests** lists failures with **Jump to Source** and **Re-run Test**. It only appears when the run actually failed — a passing run stays on Live Output.
- Run history is available from the reports flow — see [Reports & failed tests](/workflows/reports/).
- Opening or creating another project clears the live console and failed-tests list for the previous project so you never see the wrong run’s output.
