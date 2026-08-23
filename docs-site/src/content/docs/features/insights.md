---
title: Insights
description: Triage failing files from run health, then inspect index composition.
---

Insights is a triage starting point for run health — not a metrics dashboard. Open it from the activity bar (**Insights**) or the command palette.

Use it when you want to know **where the project is hurting** and jump straight into Failed Tests, source, Reports, or a rerun.

Run health is computed from the same run history as [Reports](/workflows/reports/). [Deleting a run](/workflows/reports/#delete-a-run) removes it from that history (database row and `Run-*` folder), so Insights no longer counts it. If Insights is already open, use **Refresh**.

## Run health

Once you have executed suites, the left panel (top on a narrow window) is the primary surface. Numbers are about **runs** (each time you pressed Run), not individual test cases — so a suite with 4 passes and 2 fails still counts as one **Failed** run.

**Project** / **Tag** / multi-select runs still count once in the headline strip. In the **Files** table they are broken out per `.robot` file using that run’s `output.xml`, so a full-project pass shows **Pass = 1** on each file that ran (not zero).

### Headline strip

| Label | What you are seeing |
|-------|---------------------|
| **Pass rate** | Share of finished runs that passed overall. Empty suites (**NO TESTS**) and framework crashes (**ERROR**) are left out of this rate. |
| **Runs** | How many runs Insights is counting from history (same store as [Reports](/workflows/reports/)). |
| **Failed** | How many of those runs failed. Tap to open the last failed run in Reports. |
| **Avg duration** | Average wall time of runs that recorded a duration. |

### Health cards and charts

| Signal | What you are seeing |
|--------|---------------------|
| **Pass streak** / **Fail streak** | How many newest runs in a row share the same pass or fail outcome. Tap to open that latest run in Reports. |
| **Flaky files** | Suites that have both passed and failed across history — unstable enough to triage. |
| **Interrupted** | Runs you stopped, or that never fully started. |
| **Pass rate trend** | How the recent pass rate has moved over the last few runs. |
| **Duration trend** | How long recent runs took (peak and average called out under the chart). |
| **Last run** | The newest run’s outcome and timing. Tap to open it in Reports. |
| **Failure mix by suite** | Which files account for the most failed runs. Tap a bar to open file triage. |

A short **Last N** note may appear when the newest handful of runs looks much better or worse than the overall pass rate — useful when history is long but recent health changed.

## File triage

Click a failing file in **Failure mix** or the **Files** table (for example `login.robot — 9 failed / 21 runs`). The triage dialog shows failure counts and the last failed test name when it is known, then:

| Action | Destination |
|--------|-------------|
| **Open failed tests** | Reports, on the last failed run for that file |
| **Open source** | The suite in the editor |
| **View report** | Reports for the last failed run, or the last run if none failed |
| **Rerun file** | Execution, running that `.robot` file |

Files with no failures still open in the editor.

## Composition

Composition is **secondary** — indexed shape of the project, not execution results.

After the index is ready:

| Metric | Meaning |
|--------|---------|
| Keywords / test cases / variables / … | Definitions found by the indexer |
| Suites | Distinct `.robot` files |
| Files | Distinct indexed source files (`.robot`, `.resource`, `.py`, …) |

Use **Rebuild Index** if counts look stale after adding files.

**Variables** counts user-declared names from:

- `*** Variables ***`
- `[Arguments]`
- `VAR`
- `${x}= …` assignments
- `FOR` loop variables
- YAML variable files (when indexed)

It does **not** count BuiltIn automatic variables (`${TEST_NAME}`, …) or environment `%{ENV}` references.

**Keywords** counts user keyword definitions under `*** Keywords ***`, plus public methods from indexed project `.py` libraries — not BuiltIn keywords and not call sites.

Also in Composition:

| Section | Meaning |
|---------|---------|
| Composition mix | Stacked bar of keywords / tests / variables |
| File types | Counts of `.robot`, `.resource`, `.py`, `.yaml` among indexed files |
| Focus | Density chips, index state, densest files, and test-heavy files |

**Focus** details:

- Density chips — keywords per test, symbols per file, resource and library counts
- Index state
- **Densest files** — files with the most indexed definitions (click to open)
- **Test-heavy files** — files with the most test-case definitions (click to open)

Kind rows with a count of zero stay visible but muted so small projects still show the full shape of the index.

## Files table

The Files table lists **executed `.robot` suites only** — helpers like `.py` / `.resource` and suites that have never run stay out. Indexed KW / TC / Var counts still appear next to run health. Rows load as you scroll.

| Column | Meaning |
|--------|---------|
| **File** | Suite path |
| **KW** / **TC** / **Var** | Indexed keyword, test-case, and variable definitions in that file |
| **Runs** | Times that file was part of a run |
| **Pass** / **Fail** | How many of those runs passed or failed overall |
| **Stop** | Runs that did not finish — you pressed **Stop**, or Robot never started (aborted launches are not kept in Reports) |
| **Last** | Outcome of the newest run that touched this file |

Failing rows open triage; clean rows open the file in the editor.

## First open on a large project

The first Insights open after launching a very large suite can take longer while composition and per-file run stats are computed. The spinner advances short status lines every 30 seconds while you wait. If it fails, use **Refresh** — a second open is usually fast once caches are warm.

## Related

- [Reports & failed tests](/workflows/reports/) — open logs and output, or [delete a run](/workflows/reports/#delete-a-run) from history
- [Running tests](/workflows/running-tests/) — how runs get into history
