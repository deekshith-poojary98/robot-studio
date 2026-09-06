---
title: Run, stop & re-run
description: How test execution works — toolbar runs, Tests tree, confirmation thresholds, and stop.
---

## Ways to run

| Action | Typical use |
|--------|-------------|
| **Play** (gutter left of a test name) / **Run → Run Test at Cursor** | Only the test (or task) that owns that line — no extra run configuration |
| **Run** (toolbar) / **Run → Run File** (`F5`) | Tests in the current open `.robot` file — not a text selection |
| **Project** (toolbar) / **Run → Run Project** | Entire project |
| **Tests** (activity bar) | One test, one suite, all, current file, or failed |
| **Re-run Test** | A single failure from the last run (**Failed Tests**) |

Play controls appear on `.robot` suites after the outline is ready. They use the same run configuration as toolbar **Run**. While a run is in progress the buttons stay disabled. `.resource` files and Python modules do not get play controls — use the Tests tree for those workflows.

A file or single-test run still executes parent `*** Settings ***` in `__init__.robot` (Suite Setup / Teardown). Robot Studio starts Robot at that parent folder and filters with `--suite`, so a session created in `tests/__init__.robot` is available when you run `tests/posts/posts_api.robot` or one test inside it. **Run Project** is unchanged.

## Run configurations

The toolbar selector immediately before **Run / Project / Stop** chooses a **run configuration** — a named execution context for the next run.

| Selector | Meaning |
|----------|---------|
| **Default** | No extra tags, variables, or environment pin. Uses the active toolbar environment. |
| **Smoke - Staging** (example) | Applies that configuration’s include/exclude tags, variables, variable files, and optional environment pin |

**Run** and **Project** keep their usual meaning (current file vs whole project). The selector only supplies execution context. Tests-tree **Run**, **Run Failed**, **Re-run Test**, and the editor gutter play control use the same selected configuration.

Selecting a configuration does **not** change the toolbar environment. Packages, Libraries, and language intelligence stay on the active environment. A configuration may pin an environment for **that run only**; the environment actually used is recorded on the run in Reports.

### Create and manage

From the selector: **New Configuration…** or **Manage Configurations…** (dialogs — not a new sidebar or Settings page). In Manage, **Duplicate** is a first-class action so you can clone **Smoke - Dev** into **Smoke - Staging** and change a few fields.

Configurations are stored with the project at `.robotstudio/run-configurations.json` (same Studio metadata folder as environments and reports).

Advanced Robot arguments are an escape hatch: **one argv token per row**, not a shell command.

| Allowed | Blocked (Studio-owned) |
|---------|------------------------|
| `--listener` + class/module (two rows), `--pythonpath`, `--loglevel`, … | `--outputdir`, `--output`, `--log`, `--report` (and short forms) |

Studio always attaches its own progress listener first. Your `--listener` rows run in addition. Put the flag and value on **separate** rows — a single cell like `--listener helper.Foo` is rejected.

Logs stream into **Live Output** while a run is in progress (Robot is started with unbuffered stdout so lines are not held until the process exits). The **Now Running** panel on the right shows the live call stack — suite, test, and current keyword — plus elapsed time while the run is active. After the run ends, it keeps the last location until the next start.

**Stop** cancels the run (with a confirmation that shows what is currently executing). The toolbar and status switch to **Stopping** until Robot exits — that can take a few seconds if a keyword is blocked. Output so far is kept; the HTML report may be incomplete.

## Large runs

If a project-wide run would execute more than the configured threshold (default **100** tests), Robot Studio asks for confirmation. Change the threshold in **Settings → Execution → Large Run Threshold**.

## After you stop or finish

- Finishing a run does not yank you into another view; use the **View Report** toast when you want results.
- The toolbar **Last:** chip is the outcome of that run: **Passed**, **Failed**, **No tests**, or **Error**. A keywords-only file, or a tag/filter that matches nothing, is **No tests** — not Failed.
- **Failed Tests** lists failures with **Jump to Source** and **Re-run Test**. It only appears when tests failed. A pass, or a Robot error with no tests (for example no cases matching a tag), stays on Live Output.
- Typical fix loop: Failed Tests → **Jump to Source** → edit → save → **Re-run Test** (or **Run** / `F5`) → **Reports** if you need the HTML log.
- Run history is available from the reports flow — see [Reports & failed tests](/workflows/reports/).
- Opening or creating another project clears the live console and failed-tests list for the previous project so you never see the wrong run’s output.
