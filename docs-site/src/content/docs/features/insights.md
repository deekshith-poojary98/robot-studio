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

Below the bars, **Focus** adds:

- Density chips — keywords per test, symbols per file, resource and library counts
- Index state
- **Densest files** — files with the most indexed definitions (click to open)

## Run health

Once you have executed suites, Run health shows:

| Metric | Meaning |
|--------|---------|
| Pass/Fail streak | Consecutive matching outcomes from the latest run backward |
| Flaky files | Suites that both passed and failed across history (when any) |
| Interrupted | Cancelled + aborted runs (when any) |
| Last N | Pass rate over the newest few runs when it differs meaningfully from overall |
| Duration trend | Recent runs as duration bars (color = outcome), oldest → newest; peak and average under the chart |
| Last run | Outcome, suite, duration, and passed/failed/skipped counts in plain language |
| Top failures | Suite files with the most failed runs (path variants are merged; click to open) |

Overall pass rate still appears in the headline strip above the panels.

## Files table

The Files table merges index composition with per-file run stats so you can spot hot spots (high fail counts) next to keyword/test density. Rows are built lazily as you scroll, so large projects stay responsive.

## Related

- [Reports & failed tests](/workflows/reports/) — open logs and output for a specific run
- [Running tests](/workflows/running-tests/) — how runs get into history
