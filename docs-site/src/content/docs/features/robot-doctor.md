---
title: Robot Doctor
description: Project health findings with jump-to-source for issues like missing imports.
---

**Robot Doctor** scans the open project for problems and ranks what to fix first — outside a single open file.

Open it from the activity bar (**Doctor**), **View → Robot Doctor**, `⌘⇧D` / `Ctrl+Shift+D`, or the command palette.

## What you see

| Area | Meaning |
|------|---------|
| **Findings / Critical / Errors / Warnings** | How many issues this scan found, by severity |
| **Since last scan** | Whether the count went up or down vs the previous Doctor run |
| **Fix first** | Top issues to tackle before the rest |
| **Grouped list** | Findings by type (imports, correctness, structure, past runs, …) |

Each finding expands to **Why is this reported?**, a confidence note, and **Jump to source** when a location is known.

Profiles (**Quick** / **Default** / **Full**) change how deep the scan goes. **Full** can also use patterns from past test runs.

Quick Fix actions stay hidden until they are real and trustworthy — Doctor is honest about what it can fix today versus what it can only point at.
