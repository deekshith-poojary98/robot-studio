---
title: Editor & language intelligence
description: Completions, hover, signature help, go to definition, diagnostics, and outline for Robot and Python files.
---

The editor is tuned for Robot Framework files, with lighter Python support for library modules.

## Language features

| Feature | Notes |
|---------|--------|
| Completions | **Robot:** DSL and BuiltIn keywords. After a keyword argument separator (two spaces), the popup offers the next `name=` (for example `modules=`). It stays quiet while you type the current argument’s value — including inside `expression=random.randint(`. **Python (`.py`):** buffer symbols, project-indexed symbols from other `.py` files, and Jedi-backed stdlib / venv package completions (requires an active Python environment) |
| Hover | **Robot:** pause on a **keyword** cell for docs/signature. **Python:** pause on a symbol for Jedi docs (stdlib and installed packages) |
| Signature help | **Robot:** argument hints while the caret is in a keyword call. **Python:** parameter hints from the buffer or Jedi (stdlib / venv packages) |
| Breadcrumbs | Path / structure trail above the editor |
| Go to Definition | F12 or Ctrl/Cmd+Click; multi-match picker when needed |
| References | Find usages across the project (**Go → Find References**) |
| Document symbols | Navigate within the current file (**Go → Go to Symbol in File…**) |
| Diagnostics | Live while editing Robot files; library imports resolve via the active environment. Keywords from libraries imported by a `Resource` you import are treated as available (same as Robot Framework). Extended variable access like `${response.json()}` is accepted when `${response}` is known |
| Outline | **Outline** pane under Explorer — Robot sections/keywords/tests, and Python classes/functions/methods. Click an item to jump the caret and scroll it into view |

## Problems panel

Findings sync into the bottom **Problems** panel. Missing imports share identity with Robot Doctor’s `missing_import` findings so the same issue does not feel like two different systems.
