---
title: Tests
description: Browse suites lazily, filter by status, and run tests from the tree.
---

**Tests** (activity bar / **View → Tests**) is the structural view of what you can run. The panel title in the UI is **Tests**.

## How the tree works

- Suites expand on demand (children load lazily) so large projects stay responsive
- The list is virtualized for scale
- Live filter helps you narrow by name or status

## Run from the tree

From the Tests panel you can run:

- A single test
- A suite
- All tests
- The current file
- Failed tests from the last relevant run

Toolbar **Run** still targets only the open `.robot` editor suite — not a text selection. Use the Tests tree when you need a specific test or suite node.

For very large estimated runs, Robot Studio asks for confirmation before starting (**Settings → Execution → Large Run Threshold**).
