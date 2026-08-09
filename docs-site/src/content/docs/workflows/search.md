---
title: Find code & symbols
description: Use Find in Files and Find Symbol in Project to navigate text and indexed names.
---

Robot Studio separates **text search** from **indexed symbol search** so each stays fast and predictable.

## Find in Files

Open the **Search** activity-bar icon (side panel title: **Find in Files**), or use **Edit → Find in Project…** (`⌘⇧F` / `Ctrl+Shift+F`).

- Searches project text while the editor stays mounted
- Matches can show the enclosing test, keyword, or variable when the index knows it
- File types and ignore rules are configured in **Settings → Search** (**Content Search Extensions**, **Ignore Patterns**)

## Find Symbol in Project

Open **Go → Find Symbol in Project…** (`⌘T` / `Ctrl+T`), or run **Find Symbol in Project** from the command palette.

- Searches indexed keywords, variables, and files **in the open project only**
- Best when you know the name of a keyword or variable and want to jump to its definition

There is **no Symbols activity-bar rail**. Symbol search is the Go-menu / palette flow above.

## Indexing

Indexing runs in the background when you open a project (**incremental** — unchanged files are skipped). Progress can appear in the status bar. Use **Rebuild Index** when results look stale. Common noise folders (`.venv`, `node_modules`, `.git`) are excluded.
