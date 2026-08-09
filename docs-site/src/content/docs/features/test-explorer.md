---
title: Test Explorer
description: Browse suites lazily, filter by status, and run tests from the tree.
---

Test Explorer is the structural view of what you can run.

## How the tree works

- Suites expand on demand (children load lazily) so large projects stay responsive
- The list is virtualized for scale
- Live filter helps you narrow by name or status

## Run from the tree

From a node you can run:

- A single test
- A suite
- All tests
- Failed tests from the last relevant run

For very large estimated runs, Robot Studio asks for confirmation before starting.
