---
title: Editor & language intelligence
description: Completions, hover, signature help, go to definition, diagnostics, and outline for Robot files.
---

The editor is tuned for Robot Framework files rather than generic plain text.

## Language features

| Feature | Notes |
|---------|--------|
| Completions | Split between Robot DSL and BuiltIn keywords. After a keyword argument separator (two spaces), the popup offers the next `name=` (for example `modules=`). It stays quiet while you type the current argument’s value — including inside `expression=random.randint(` |
| Hover | Pause on a **keyword** cell for docs/signature. Arguments and variables do not open the card — so lines with several keywords (e.g. `Run Keyword If … Log …`) show the keyword under the pointer |
| Signature help | Argument hints while the caret is in a keyword call (typing), separate from mouse hover |
| Breadcrumbs | Path / structure trail above the editor |
| Go to Definition | F12 or Ctrl/Cmd+Click; multi-match picker when needed |
| References | Find usages across the project (**Go → Find References**) |
| Document symbols | Navigate within the current file (**Go → Go to Symbol in File…**) |
| Diagnostics | Live while editing; library imports resolve via the active environment |
| Outline | **Outline** pane under Explorer |

## Problems panel

Findings sync into the bottom **Problems** panel. Missing imports share identity with Robot Doctor’s `missing_import` findings so the same issue does not feel like two different systems.
