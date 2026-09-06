---
title: Robot Doctor
description: Structural project health — circular imports, duplicate keywords, potentially unused assets.
---

**Robot Doctor** scans the open project for **structural problems that span files** — issues a single open file’s Problems list often will not show.

Open it from the activity bar (**Doctor**), **View → Robot Doctor**, `⌘⇧D` / `Ctrl+Shift+D`, or the command palette. Click **Scan project**.

## What Doctor owns

| Check | Severity | Meaning |
|-------|----------|---------|
| **Circular imports** | Error | Resources/suites import each other in a cycle |
| **Duplicate keywords** | Error | Same keyword name defined in more than one place |
| **Potentially unused keywords / resources** | Info | No static callers/imports found — confirm before deleting |

## What Doctor does **not** own

| Question | Use instead |
|----------|-------------|
| What’s wrong in this file? | **Problems** |
| Why did my test fail? | **Execution / Reports → Failed Tests** |
| Missing `Resource` / `Library` while editing | **Problems** / editor diagnostics |
| Project composition / run trends | **Insights** |
| Where is this symbol? | **Go → Find Symbol in Project…** |

## Finding details

Use **Fix first** to jump to the highest-priority items — click a row to expand that finding in the list below (and scroll to it).

Expand a finding to see:

- **Why this matters** — plain-language explanation
- **Import cycle** (when applicable) — `a → b → a`
- **Affected files** — click a row to open it
- **Open source** — jump to the primary location

Unused findings are deliberately conservative. Shared libraries, dynamic keyword names (`Run Keyword If`, `Wait Until Keyword Succeeds`, keyword names passed as arguments), and reserved helpers can look unused to the static graph.
