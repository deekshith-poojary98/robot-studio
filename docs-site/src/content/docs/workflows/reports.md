---
title: Reports & failed tests
description: Browse run history, open Robot HTML reports, and jump back to failures.
---

## Run history

Runs are listed by run number from `.robotstudio/reports/Run-*` (legacy root `Reports/` paths remain readable when stored). The active run in the sidebar is highlighted so you can see which details are open.

Each run entry shows stats and links to the artifacts Robot Framework produced. Failure counts stay emphasized; there is no pass/fail status badge on the details header. Run details also show the **configuration** used for that run (**Default** when none was selected).

- `report.html`
- `log.html`
- `output.xml`

## Failed tests

Failed runs surface a **Failed Tests** section on the run details page (same data as Live Execution):

- Failure message from Robot
- Source location
- **Jump to Source** — open the failing test at the right place
- **Re-run Test** — execute just that failure again

After a live run finishes, the same list also appears on the Execution page.

## Flow tip

When a run finishes, stay in context and open the report from the toast when you are ready. Clickable run status in the chrome returns you to **Tests** if you want the suite tree again.

From [Insights](/features/insights/), **Last run**, fail streak, headline **Failed**, and file triage **Open failed tests** / **View report** land on this same Reports view.
