---
title: Editor & language intelligence
description: Completions, hover, signature help, go to definition, diagnostics, and outline for Robot and Python files.
---

The editor supports both Robot Framework suites and the Python modules beside them. Python intelligence (`.py`, `.pyi`, `.pyw`) is backed by [Jedi](https://jedi.readthedocs.io/) and resolves against your **active environment**, so completions and hover reflect the packages you actually installed.

## Language features

| Feature | Notes |
|---------|--------|
| Completions | Each row is tagged with what the symbol is (`param`, `class`, `def`, `module`, …) so same-prefix entries are easy to tell apart. Press **Tab** or **Enter** to accept. **Robot:** DSL and BuiltIn keywords. After a keyword argument separator (two spaces), the popup offers the next `name=` (for example `modules=`). It stays quiet while you type the current argument’s value — including inside `expression=random.randint(`. **Python:** buffer symbols (locals and parameters in scope first), project-indexed symbols from other modules, and stdlib / installed-package symbols. Private `_names` appear once you type the leading underscore |
| Hover | **Robot:** pause on a **keyword** cell for docs/signature. **Python:** pause on a symbol — including builtins like `len` and `str.split`, stdlib modules, and packages in the active environment |
| Signature help | Sits just above the caret line (never under the completion popup). While typing it shows parameter chips and a short summary; pause on the symbol for the full docstring. **Robot:** argument hints while the caret is in a keyword call. **Python:** parameter hints while you fill in a call, or from the buffer while you write a `def` header — it does not stay pinned over the function body |
| Breadcrumbs | Path / structure trail above the editor, including the enclosing Robot keyword or Python class/function |
| Go to Definition | F12 or Ctrl/Cmd+Click; multi-match picker when needed. Results stay in the **open workspace** — a project you opened earlier is not mixed in. **Python:** follows imports and aliases to where a name is defined; stdlib / site-package sources open in **Peek Definition** (outside the project tree) |
| References | Find usages across the project (**Go → Find References**). **Python:** resolved from the caret, so it distinguishes same-named symbols in different scopes |
| Rename Symbol | Command palette → **Rename Symbol** (Python). Renames the definition and every usage across the project, including files that are not open |
| Document symbols | Navigate within the current file (**Go → Go to Symbol in File…**) |
| Diagnostics | Live while editing. **Robot:** library imports resolve via the active environment; keywords from libraries imported by a `Resource` you import are treated as available (same as Robot Framework), and extended variable access like `${response.json()}` is accepted when `${response}` is known. **Python:** syntax errors (all of them, not just the first) plus undefined names, unused imports, and unused locals |
| Formatting | **Robot:** built-in tidy. **Python:** uses your environment’s own `ruff` or `black` so the result matches your project config and CI. With neither installed, only trailing whitespace is trimmed |
| Outline | **Outline** pane under Explorer — Robot sections/keywords/tests, and Python classes, functions, methods, and variables (module-level names, class fields, and `self.` / `cls.` attributes). Click an item to jump the caret and scroll it into view; the selection follows your caret as you move through the file |
| Run this test | In a `.robot` suite, a play control sits left of each test case (and task) name. Click it to run only that test. **Run → Run Test at Cursor** (command palette: **Run Test at Cursor**) does the same for the test that contains the caret. Toolbar **Run** / `F5` still runs the whole file |

## Typing in Python files

| Key | Behavior |
|-----|----------|
| **Tab** | Accepts the highlighted completion when the popup is open, otherwise indents |
| **Enter** | Accepts the highlighted completion when the popup is open. After a line ending in `:` (`def`, `class`, `if`, `for`, `try`, `match`) it opens an indented block |
| **Cmd/Ctrl+Click** | Go to definition of the symbol under the pointer |

## Problems panel

Findings sync into the bottom **Problems** panel. Missing imports share identity with Robot Doctor’s `missing_import` findings so the same issue does not feel like two different systems.

The panel **auto-opens** when diagnostics first appear while you edit. It **auto-closes** when those findings clear — only if Studio opened it **and** Problems is still the visible tab. If you opened Problems yourself (View menu, status bar ERRORS/WARNINGS, or the collapsed bar), or you switched to **Terminal**, the panel stays open.

Python diagnostics need an active environment. While a file has a syntax error only the parse errors are shown — reporting undefined names in a half-typed file would flag symbols whose definitions simply have not parsed yet.
