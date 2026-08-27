---
title: Run your first tests
description: Run a Robot file or project and open the report when you are done.
---

With a project open and an environment active, you are ready to execute.

## Save before you run

By default, **Save Before Run** is on (**Settings → Editor**), so pending edits are written when a run starts. You can also save manually with `⌘S` / `Ctrl+S` (**File → Save**) or **Save All**.

## Quick run from the toolbar

The quiet toolbar keeps the essentials visible:

- **Default** (or a named run configuration) — execution context for the next run; **Default** uses the active environment with no extra tags or variables. See [Run configurations](/workflows/running-tests/#run-configurations).
- **Run** — run the **current open `.robot` suite** in the editor (`F5`, or **Run → Run File**). It does **not** run a text selection or an Explorer file selection.
- **Play** (left of a test name) — run **only that test**. Same action: **Run → Run Test at Cursor**.
- **Project** — run the whole project (menu: **Run → Run Project**)
- **Stop** — cancel an in-progress run (`Shift+F5`)

Live logs stream while tests execute. When a run finishes, Robot Studio stays on your current view and offers a **View Report** toast so you can open results when you are ready.

## Use Tests

1. Open the **Tests** activity-bar view (**View → Tests**).
2. Expand a suite to load its children (the tree loads lazily for large projects).
3. Run a single test, a suite, all tests, the current file, or **failed** tests from a previous run from the tree/toolbar actions.
4. Filter by name or status while the tree is open.

Large project runs ask for confirmation when the estimated count is high (default threshold: **100** tests — change it in **Settings → Execution → Large Run Threshold**).

## After the run

- Open HTML **report** / **log** from the run details or toast.
- Use **Failed Tests** to **Jump to Source** or **Re-run Test** for a single failure.
- Clickable run status in the chrome jumps back to **Tests** when you want the tree again.

## Next step

→ [Write and edit tests](/workflows/writing-tests/) · or skim [keyboard shortcuts](/tips/keyboard-shortcuts/)
