---
title: Impact Analysis
description: See which tests are affected by a keyword change, with confidence and why.
---

When you change a shared keyword, Impact Analysis answers **which tests should you re-run?** — not only where the name appears (that is [Find References](/workflows/search/)).

## Open Impact Analysis

1. Open a Robot file and place the caret on a **user keyword** name (or select the keyword in the outline).
2. Run **Impact Analysis** from:
   - **Command Palette** (`⌘⇧P` / `Ctrl+Shift+P`) → **Impact Analysis**
   - **Go → Impact Analysis**
3. A right-hand **Impact** panel lists affected tests.

Requires an open project with a built analysis graph (open the project and wait for indexing / rebuild if the panel says the graph is empty).

## Read the results

| Section | Meaning |
|---------|---------|
| **Affected** | Tests the graph reaches with non-low confidence |
| **Uncertain** | Low-confidence bindings — review before treating as certain |

Each row shows:

- Test name
- File, relation (**Direct** / **Transitive** / **Import**), and confidence
- A short **why** line (for example, that the test calls the keyword)

Click a row to jump to that test in the editor. Close the panel with the **X**.

## Tips

- Prefer Impact when deciding what to re-run after editing a shared keyword.
- Use **Find References** when you need every textual / index occurrence of a name.
- **Run Impact Set** (run only the listed tests) is planned; for now, run the listed files or tests from **Tests** / the toolbar.

## Related

- [Write and edit tests](/workflows/writing-tests/)
- [Find code & symbols](/workflows/search/)
- [Run, stop & re-run](/workflows/running-tests/)
- [Roadmap](/getting-started/roadmap/) — Impact Analysis is the flagship post-beta semantic workflow
