---
title: Editor & language intelligence
description: Completions, hover, go to definition, diagnostics, and outline for Robot files.
---

The editor is tuned for Robot Framework files rather than generic plain text.

## Language features

| Feature | Notes |
|---------|--------|
| Completions | Split between Robot DSL and BuiltIn keywords |
| Hover | Keyword / symbol information as you pause |
| Go to Definition | F12 or Ctrl/Cmd+Click; multi-match picker when needed |
| References | Find usages across the project |
| Document symbols | Navigate within the current file |
| Diagnostics | Live while editing; library imports resolve via the active environment |
| Outline | Document outline under Explorer |

## Problems panel

Findings sync into the bottom **Problems** panel. Missing imports share identity with Robot Doctor’s `missing_import` findings so the same issue does not feel like two different systems.
