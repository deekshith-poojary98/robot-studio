---
title: Reports & failed tests
description: Browse run history, open Robot HTML reports, and jump back to failures.
---

## Run history

Runs are listed by run number from `.robotstudio/reports/Run-*` (legacy root `Reports/` paths remain readable when stored).

Each run entry shows pass/fail stats and links to the artifacts Robot Framework produced:

- `report.html`
- `log.html`
- `output.xml`

## Failed tests

After a run, **Failed Tests** gives you a short path back into the code:

- **Jump to Source** — open the failing test at the right place
- **Re-run Test** — execute just that failure again

## Flow tip

When a run finishes, stay in context and open the report from the toast when you are ready. Clickable run status in the chrome returns you to Tests if you want the explorer again.
