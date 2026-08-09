---
title: Find code & symbols
description: Use Find in Files and Symbols search to navigate keywords, variables, and text.
---

Robot Studio separates **text search** from **indexed symbol search** so each stays fast and predictable.

## Find in Files

Open the left **Search** rail (`⌘⇧F` / `Ctrl+Shift+F`).

- Searches project text while the editor stays mounted
- Matches can show the enclosing test, keyword, or variable when the index knows it
- File types scanned are configurable via `ROBOT_STUDIO_CONTENT_SEARCH_EXTENSIONS`

## Symbols

Open **View → Symbols** or use the command palette.

- Searches indexed keywords, variables, and files
- Best when you know the name of a keyword or variable and want to jump to its definition

## Indexing

Indexing runs in the background when you open a project (**incremental** — unchanged files are skipped). Progress can appear in the status bar. Use **Rebuild Index** when results look stale. Common noise folders (`.venv`, `node_modules`, `.git`) are excluded.
