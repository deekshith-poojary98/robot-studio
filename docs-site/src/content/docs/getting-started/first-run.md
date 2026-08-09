---
title: Run your first tests
description: Run a Robot file or project and open the report when you are done.
---

With a project open and an environment active, you are ready to execute.

## Quick run from the toolbar

The quiet toolbar keeps the essentials visible:

- **Run** — run the current editor file (or focused selection when applicable)
- **Run Project** — run the whole project
- **Stop** — cancel an in-progress run

Live logs stream while tests execute. When a run finishes, Robot Studio stays on your current view and offers a **View Report** toast so you can open results when you are ready.

## Use Test Explorer

1. Open the **Test Explorer** view.
2. Expand a suite to load its children (the tree loads lazily for large projects).
3. Run a single test, a suite, all tests, or **failed** tests from a previous run.
4. Filter by name or status while the tree is open.

Large project or tag runs ask for confirmation when the estimated count is high (default threshold: 100 tests). That protects you from accidentally kicking off a huge suite.

## After the run

- Open HTML **report** / **log** from the run details or toast.
- Use **Failed Tests** to jump to source or **Re-run Test** for a single failure.
- Clickable run status in the chrome jumps back to Tests when you want the explorer again.

## Next step

→ [Write and edit tests](/workflows/writing-tests/) · or skim [keyboard shortcuts](/tips/keyboard-shortcuts/)
