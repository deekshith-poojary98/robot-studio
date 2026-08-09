---
title: Insights
description: Project composition and run health — symbols, pass rate, duration trend, and failing files.
---

Insights is a center view for how the project is shaped and how recent runs are doing. Open it from the activity bar (**Insights**) or the command palette.

## Composition

After the index is ready, Composition shows **indexed** counts:

| Metric | Meaning |
|--------|---------|
| Keywords / test cases / variables / … | Definitions found by the indexer |
| Suites | Distinct `.robot` files |
| Files | Distinct indexed source files (`.robot`, `.resource`, `.py`, …) |

Use **Rebuild Index** if counts look stale after adding files. Composition is **not** “tests executed in the last run” — that lives under Run health / Reports.

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

## Run health

Once you have executed suites, Run health shows:

| Metric / chart | Meaning |
|----------------|---------|
| Pass/Fail streak · Flaky · Interrupted · Last N | Compact signals in the metric row |
| Outcome share | Thin bar of passed / failed / cancelled / aborted runs |
| Pass rate trend | Rolling pass-rate sparkline (window of up to 5), oldest → newest |
| Duration trend | Duration bars (colored by outcome) with a muted tests-count line overlaid |
| Last run | Outcome, suite, duration, and passed/failed/skipped counts in plain language |
| Failure mix by suite | Horizontal bars for the hottest failing files (click to open) |

Overall pass rate still appears in the headline strip above the panels.

## Files table

The Files table merges index composition with per-file run stats so you can spot hot spots (high fail counts) next to keyword/test density. Rows are built lazily as you scroll, so large projects stay responsive.

## Related

- [Reports & failed tests](/workflows/reports/) — open logs and output for a specific run
- [Running tests](/workflows/running-tests/) — how runs get into history
