---
title: Insights
description: Triage failing files from run health, then inspect index composition.
---

Insights is a triage starting point for run health — not a metrics dashboard. Open it from the activity bar (**Insights**) or the command palette.

Use it when you want to know **where the project is hurting** and jump straight into Failed Tests, source, Reports, or a rerun.

## Run health

Once you have executed suites, the left panel (top on a narrow window) is the primary surface:

| Signal | What it does |
|--------|----------------|
| Headline **Failed** | Opens the last failed run in [Reports](/workflows/reports/) |
| Fail / pass streak | Opens that last run in Reports so you can see why the streak exists |
| Flaky files | Opens triage for files that both passed and failed |
| Last run | Opens that run in Reports |
| Failure mix by suite | Opens triage for the hottest failing file |

Duration and pass-rate trends stay as context. They do not add extra destinations.

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

The Files table merges index composition with per-file run stats so you can spot hot spots (high fail counts) next to keyword/test density. Rows are built lazily as you scroll, so large projects stay responsive. Failing rows open triage; clean rows open source.

## Related

- [Reports & failed tests](/workflows/reports/) — open logs and output for a specific run
- [Running tests](/workflows/running-tests/) — how runs get into history
