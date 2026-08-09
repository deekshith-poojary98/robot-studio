---
title: Run, stop & re-run
description: How test execution works — toolbar runs, Test Explorer, confirmation thresholds, and stop.
---

## Ways to run

| Action | Typical use |
|--------|-------------|
| **Run** (toolbar) | Current file / focused scope |
| **Run Project** | Entire project |
| **Test Explorer** | One test, one suite, all, or failed |
| **Re-run Test** | A single failure from the last run |

Logs stream into **Live Output** while a run is in progress (Robot is started with unbuffered stdout so lines are not held until the process exits). The **Now Running** panel on the right shows the current suite, test, and keyword (same idea as RIDE’s execution tree).

**Stop** cancels the run (with a confirmation that shows what is currently executing). Output so far is kept; the HTML report may be incomplete.

## Large runs

If a project or tag run would execute more than the configured threshold (default **100** tests), Robot Studio asks for confirmation. That keeps accidental full-suite runs from eating your afternoon.

Developers can change the threshold with `ROBOT_STUDIO_LARGE_RUN_THRESHOLD` — see [Settings reference](/reference/settings/).

## After you stop or finish

- Finishing a run does not yank you into another view; use the **View Report** toast when you want results.
- **Failed Tests** lists failures with **Jump to Source** and **Re-run Test**.
- Run history is available from the reports flow — see [Reports & failed tests](/workflows/reports/).
- Opening or creating another project clears the live console and failed-tests list for the previous project so you never see the wrong run’s output.
