---
title: Write and edit tests
description: Everyday editing in Robot Studio — files, outline, diagnostics, and navigation.
---

## Open and create files

Use the **Explorer** to browse your project. You can:

- Create new files and folders
- Create a `.robot` file with a Settings / Variables / Test Cases / Keywords scaffold
- Rename (including case-only renames), duplicate, delete, and drag-move
- Multi-select with ⌘/Ctrl and Shift for bulk actions
- Copy path(s) and reveal in the OS file manager

## Edit with confidence

The Robot editor is multi-tab and understands Robot Framework structure:

- Completions for Robot DSL and BuiltIn keywords
- Hover information and signature help while you type keyword calls
- Editor breadcrumbs for the current file path / structure
- **Go to Definition** (F12 or Ctrl/Cmd+Click), with a picker when multiple matches exist
- Find references and document symbols (**Go → Go to Symbol in File…**)
- Live diagnostics while you type (including library imports resolved through the active environment)
- Document **Outline** under Explorer for jumping within the file

## Save

- **File → Save** (`⌘S` / `Ctrl+S`) and **Save All** (`⌘⇧S` / `Ctrl+Shift+S`)
- Optional **Auto Save** in **Settings → Editor** (off by default)
- **Save Before Run** is on by default so runs pick up unsaved edits

Problems appear in the bottom **Problems** panel and stay in sync as you edit. Click a finding to jump to the line and column. The status bar ERRORS / WARNINGS shortcut opens that panel quickly.

## Find and replace

Use the editor find/replace for the current file (**Edit → Find…** / **Replace…**). For project-wide search, see [Find code & symbols](/workflows/search/).

## Keep the shell out of the way

The native window menu (File / Edit / View / Go / Run / Terminal) and the quiet toolbar keep project, environment, branch, and run actions close without crowding the editor.
