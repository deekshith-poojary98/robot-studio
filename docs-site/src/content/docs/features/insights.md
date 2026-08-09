---
title: Insights
description: Project composition and run health — symbols, pass rate, duration trend, and failing files.
---

Insights is a center view for how the project is shaped and how recent runs are doing. Open it from the activity bar (**Insights**) or the command palette.

## Composition

After the index is ready, Composition shows counts for keywords, test cases, suites, resources, libraries, variables, and files. Use **Rebuild Index** if counts look stale.

## Run health

Once you have executed suites, Run health shows:

| Metric | Meaning |
|--------|---------|
| Pass rate | Share of counted runs that passed |
| Avg duration | Mean wall time across runs with a duration |
| Pass / Fail | Outcome totals for the project |
| Pass/Fail streak | Consecutive matching outcomes from the latest run backward |
| Duration trend | Recent runs as duration bars (color = outcome), oldest → newest |
| Last run | Outcome, suite, duration, test counts, and relative time |
| Top failures | Files with the most failed runs (click to open) |

**View in Reports** jumps to the report browser for artifacts from those runs.

## Files table

The Files table merges index composition with per-file run stats so you can spot hot spots (high fail counts) next to keyword/test density.

## Related

- [Reports & failed tests](/workflows/reports/) — open logs and output for a specific run
- [Running tests](/workflows/running-tests/) — how runs get into history
