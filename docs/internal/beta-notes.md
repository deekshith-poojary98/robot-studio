# Beta Notes

Chronological log for beta testers and maintainers.  
If you think “didn’t I already fix that?”, look here first.

Tags: `[Trust]` · `[Identity]` · `[Lifecycle]` · `[Autosave]` · `[Execution]` · `[Packaging]` · `[UI]` · `[Appearance]`

---

## Fixed

- 2026-08-12

  **[Packaging]**
  - Private beta distribution is **GitHub Releases** (zips for macOS / Windows / Linux via **Package Desktop** Actions). Not an installer. Install guide and README updated.

  **[Trust]**
  - P0 exit met. Remaining highlighter / completion sweeps deferred to GitHub issues. Toolbar Stop spacing already shipped as the segmented Run / Project / Stop control.

  **[UI]**
  - Font Family lists **monospace fonts installed on the machine** (Menlo default). The earlier curated 10-name list is gone.

  **[Docs]**
  - Testers file bugs on GitHub Issues. In-app Send Feedback is deferred. User guide onboarding is no longer blocked on a side-channel artifact once a Release is published.

- 2026-08-09

  **[UI]**
  - Execution idle subtitle said “toolbar or Test Explorer” while the activity bar / guide say **Tests**. Updated to **Tests**; regression in `frontend/test/execution_page_test.dart`.

  **[Docs]**
  - User guide content validation **PASS** against shipped product (selection-run / Symbols / Settings UI / Tests naming / private-beta install honesty).

  **[Doctor]**
  - Doctor Value Pass — structural-only scanner. Removed Quick/Default/Full UX; scan runs circular imports, duplicate keywords, potentially unused keywords/resources. Demoted missing_import (Problems), large_keyword, and execution smells (Insights/Reports). Findings show why / cycle / affected files / Open source. Unused findings are INFO + conservative copy.

- 2026-08-05

  **[Trust]**
  - Emergency Lane cleared — audited; nothing qualified (crash / data loss / wrong suite / cannot open / identity corruption / severe perf).

  **[Execution]**
  - Wrong Run target — extracted `resolveRunTargetPath`; refuses sticky suite while a non-`.robot` editor is focused; regression in `frontend/test/run_target_test.dart`.

  **[Autosave]**
  - Quiet failures on missing project — cancel pending auto-save when project disappears; status line only (no dialog spam). Backend already refuses writes that would resurrect a deleted workspace.

  **[Identity]**
  - Recreate env same name — after Finder-delete of active venv folder, creating `venv` again activates the new env (ghost row purged before `create_venv`); `test_recreate_same_name_after_folder_delete_activates_new`.

  **[Lifecycle]**
  - File → Close Project — returns to the welcome/landing screen; prompts on dirty tabs; also in command palette. Live stream reconnects on next open.
  - Standalone Close unloads session — closing a missing standalone project clears env chips; `_applyOpenedWorkspace` clears `environments` before reload so `venv · missing` cannot stick across Close → New Project same name.

  **[Syntax]**
  - Keyword name turned teal after a whitespace-only line — indented-call rules used `\s`, which matches newlines, so `    \n` swallowed the next column-0 keyword name (`Type` painted as a library call). Indent/separator classes are now `[ \t]`; regression in `frontend/test/editor_trust_fixes_test.dart`.

  **[UI]**
  - Settings is a full screen, not a dialog — `PreferencesPage` takes the center view with a category rail (Editor · Execution · Search · Appearance), so new categories no longer have to fit a 480px modal. Header carries Restore Defaults / Discard / Save; Save and Discard stay disabled until the draft actually differs, and an "Unsaved changes" line replaces the silent modal. Regression in `frontend/test/preferences_page_test.dart`.
  - Settings page went stale on external changes — toggling Word Wrap from Edit ▸ Word Wrap (or the palette) while Settings was open left the switch showing the old value, and Save would then write it back. `PreferencesPage` now listens to `AppSettingsController` and three-way merges: fields you haven't touched take the external value, fields you're mid-edit keep yours. Text fields only reset when their value moved, not their formatting, so the caret survives.
  - Settings is no longer buried under File — a gear at the bottom of the sidebar rail opens it (highlighted while open), and it works with no project loaded. File menu and command palette now say **Settings** instead of **Preferences**; ⌘, is unchanged.
  - Outline kept the last file's symbols after every tab was closed — closing the final tab cleared `documentOutline` (the legacy flat list) but not `documentAnalysis`, and the tree renders from `documentAnalysis.root`, so the old suite stayed on screen with no editor open. Teardown is now one `EditorShellController.clearActiveDocument()` used by both close paths and by `reset()`, so they can't drift; it also drops stale folding ranges, diagnostics, hover and cursor position. The outline filter now resets when the file changes instead of silently hiding symbols in the next file. Regressions in `frontend/test/document_outline_test.dart` and `editor_status_notice_test.dart`.
  - Outline: **Collapse All** button next to the filter, and `[Documentation]` no longer appears as a child of keywords / test cases / settings (the text still shows on hover).
  - Search PyPI dialog rebuilt on the house dialog pattern — it was the one dialog still using raw Material defaults: a 24px `headlineSmall` title, full-size `ListTile` rows, oversized buttons, and a hardcoded `height: 480` that left a large empty void whether there were 0 results or 3. Now compact chrome (`titleLarge` title, 20px paddings), dense result rows (12.5px name / 11px meta), a results list that sizes to content up to 236px, and Install moved into the actions bar next to Close so accent lands on one CTA instead of a teal button on every row. Results are selected by tapping the row (highlight + check).
  - Package Manager can import `requirements.txt` / `.in` — **Import requirements** opens a native file picker, confirms the target and warns that pinned requirements may upgrade or downgrade existing packages, then runs `pip install -r` against the active environment (never system Python). The backend validates existence, type and a 2 MB size cap; completion refreshes packages and Robot Framework status. Regressions in `backend/tests/test_package.py`, `test_package_api.py`, and `frontend/test/widget_test.dart`.
  - Library keyword docs now show the complete Libdoc docstring — resolution previously preferred `kw.short_doc`, silently throwing away everything after the one-line summary even though `kw.doc` was available. The detail pane now renders the full text as selectable documentation: headings, paragraphs, bullets/numbered steps, bold/italic/inline code, tables and pipe-formatted examples. Unknown syntax is preserved verbatim rather than dropped. Regressions in `backend/tests/test_language_env_libraries.py` and `frontend/test/robot_documentation_test.dart`.
  - Keyword docs render **both dialects**: Robot Framework markup (older libraries) and Markdown (what newer libraries increasingly ship). The renderer picks a dialect from libdoc's `doc_format`, which comes from a library's `ROBOT_LIBRARY_DOC_FORMAT` and is now carried end to end (`resolve_library` → `KeywordMetadata`/`LibraryMetadata` → `/language/libraries/{name}` → `LibraryKeywordInfo.docFormat`). Because libdoc defaults that field to `ROBOT`, a library that writes Markdown without declaring it would still arrive as `ROBOT`, so an undeclared `ROBOT` is sniffed instead of trusted: Markdown-only markers (fences, `#` headings, `**bold**`, `[text](url)`, `|---|` rows) are scored against Robot-only markers (`= Heading =`, ` ``code`` `, `| ` blocks) and the higher score wins. An explicitly declared format is never overridden. `TEXT`/`REST` show verbatim; `HTML` is normalised to Robot markup rather than printed as tag soup.
  - Two formatting bugs in the same pane, both from treating Robot markup as Markdown-ish. Inline code was matched with **single** backticks, but Robot uses double (` ``code`` `) — so ` ``Add Sheet`` … ``WorkbookNotOpenError`` ` matched from the *second* backtick of the first pair to the *first* of the next, highlighting a whole sentence of prose as code. And `| ` example blocks kept their leading pipes; libdoc strips that marker, so Settings/Keywords/Test Cases tables now read as plain preformatted text. Robot rules now follow libdoc's own `htmlformatters` precedence (table → preformatted → list → heading → ruler → paragraph), which also means `*bold*` respects word boundaries (`2 * 3 * 4` stays literal), a single backtick is a keyword *link* rather than code, `- ` is the only bullet marker, and paragraphs wrap instead of breaking at source newlines.
  - Run / Run Project / Stop are one attached segmented bar instead of three separate buttons with gaps — a single rounded rectangle with 1px hairline splits, every segment the same width (sized to the widest label) and height (`AppControlHeight.toolbarAction`). "Run Project" shortened to **PROJECT** so equal-width segments don't leave the other two half empty. Run stays accent-filled, Stop still turns red only while a run is active. Regression in `frontend/test/ux_polish_ab_test.dart` measures widths, heights and the zero gap.
  - Outline pane is vertically resizable — the divider between the file tree and OUTLINE is now a drag sash (resize cursor, 7px hit area) instead of a fixed 220px box. Range is 96px up to the Explorer height minus room for the tree, and double-clicking the sash restores the default. Regression in `frontend/test/document_outline_test.dart`.
  - Local diagnostic logs — Robot Studio now writes daily files under `~/.robot-studio/logs/` (`frontend-YYYY-MM-DD.log`, `backend-YYYY-MM-DD.log`). File logging runs in release builds too (console stays debug-only). On every startup both sides delete `*.log` files older than **7 days** so support can ask for a recent log without filling the user's disk. Passwords / tokens / file contents stay redacted via the existing body summarizer. Regressions in `backend/tests/test_logging_setup.py` and `frontend/test/app_logger_test.dart`.
  - Font Family is a dropdown of the top 10 IDE monospace faces (Menlo, JetBrains Mono, Fira Code, Cascadia Code, Consolas, Source Code Pro, Monaco, Roboto Mono, IBM Plex Mono, Courier New) instead of a free-text field that silently fell back on typos. A previously saved custom name still appears so we don't clobber it. Regressions in `frontend/test/editor_font_families_test.dart` / `preferences_page_test.dart`.

  **[Execution]**
  - **Re-run Failed did nothing** whenever the failing run had targeted a single file or test. It re-ran with `--rerunfailed <output.xml>` against the *project root*, but Robot resolves the long names inside output.xml against the original run's target: a failure recorded while running `tests/demo.robot` is stored as `Demo.Beta`, which matches nothing under the project root where the same test is `Proj.Tests.Demo.Beta`. Robot exited 252 with `contains no tests or tasks matching name 'Demo.Beta'` and produced no results. Re-run Failed now targets each failed test through the suite file that recorded it (`--test Beta …/tests/demo.robot`), reusing the same grouping as Run Selected, and only falls back to `--rerunfailed` when output.xml has no usable sources.
  - **A failed run could vanish and blame the wrong thing.** Any run that exited non-zero, produced no `output.xml`, and took under 3 seconds was deleted outright — status reset to `idle`, run detached, history entry removed — and reported as "Robot Framework did not produce results. Confirm Robot Framework is installed in the active environment." That heuristic existed for a broken environment, but it also swallowed every fast, legitimate Robot rejection: a bad option, a filter matching no tests, invalid suite data. The real message was discarded and Robot was blamed for not being installed when it was. Now the run is only discarded when the console actually says Robot could not be imported (or produced no output at all); otherwise it stays visible as **failed** with its exit code and Robot's own `[ ERROR ]` line carried on the event. Regressions in `backend/tests/test_test_explorer_api.py`.

  **[Appearance]**
  - Theme → Light did nothing — the preference saved and `AppShell` even resolved a light `ThemeData`, but nothing read it: every surface, border and label came from `AppColors`, a class of `static const` **dark** hex values (593 references across 72 files). Swapping `ThemeData` repainted almost nothing. Two further breaks sat underneath: `buildLightAppTheme()` was `buildAppTheme().copyWith(...)`, so it inherited the dark `textTheme`/`listTileTheme` (near-white text on light surfaces), and the `Theme` was applied *inside* `AppShell.build`, below the shell's own `State.context`.
    - Colour tokens are now `AppPalette`, a `ThemeExtension` with dark and light variants, read as `context.palette`. Widgets depend on it through `Theme.of`, which is why even `const` widgets repaint on a theme switch — a mutable global would not have.
    - `buildAppTheme(palette)` builds both brightnesses from one function, so light can't inherit dark foregrounds.
    - Theme now lives on `MaterialApp` (`theme` / `darkTheme` / `themeMode`) with the preference published up from the shell, so dialogs, menus and the shell itself all follow it — and `system` tracks the OS, including live changes.
    - Editor highlighting has a real light palette: Robot grammar switches VS Code **Dark+** → **Light+** (`#DCDCAA` yellow is ~1.5:1 on white), and the terminal's ANSI ramp inverts its black/white ends.
    - `AppColors` is gone from `lib/`. Guards: `frontend/test/app_theme_test.dart` (palette wiring, const-widget repaint, WCAG contrast for both brightnesses), `editor_syntax_test.dart` (Dark+/Light+ token maps), and a `widget_test.dart` case that sets Light end-to-end and fails if any surface is still painted from a dark token.

  **[Trust]**
  - Library Explorer scoped to open workspace — stopped listing `Library` imports from other projects (Browser / RequestsLibrary / generate_robot_tests ghosts). `"Open to load"` with empty pane = import present but package not in active env.
  - Settings reset compile fix — `POST /settings/reset` now sends `body: {}`.

- 2026-08-06

  **[UI]**
  - Execution header no longer shows the FINISHED / RUNNING · timer status badge — status already lives in Recent Runs and the toolbar. Title + subtitle only.
  - Test Explorer now lists only `.robot` files that declare `*** Test Case(s) ***` or `*** Task(s) ***`. Resource and keyword-only Robot files no longer appear as empty runnable suites; singular section aliases also expose their test/task children correctly.
  - Cold start restores the last project (or workspace) by default — Settings → Appearance → **Restore Last Project**. Missing paths soft-fail to welcome with no modal; editor tabs are not restored yet.
  - Settings → Appearance → **Accent** offers the top IDE accents (Teal default, Electric Blue, Purple, Mint, Warm Orange, Soft Gold, Coral, Crimson, Burnt Amber, Slate). Neon theme hexes are UI-tuned for light/dark chrome; Save rebuilds `AppPalette` on `MaterialApp`. Legacy `green`/`rose` map to Mint/Coral.
  - Package search accepts partial matches and ranks **exact → prefix → substring → fuzzy** (ordered subsequence, min 2 chars). Hyphen/underscore/dot are normalized; results stay deterministic — no aggressive typo engine. Applies to **Search installed** and PyPI. PyPI HTML search is bot-blocked, so discovery uses the cached Simple API name index and shows the **top 20** ranked packages (best match first) with JSON metadata for version/summary.
  - Installing a package version that is already present prompts **Cancel** / **Force Install** instead of a silent no-op. Force runs `pip install --force-reinstall`.
  - Reports empty state no longer shows the “No runs yet…” banner or a **Run Suite** button — title + “No run selected” only; run from the toolbar / Tests explorer.
  - Bottom panel drops the **Console** tab (internal Studio status noise). Tabs are **Terminal · Problems**; shell events still go to `AppLogger` / the log file.
  - Package Manager **Export requirements** freezes the active environment (`pip freeze`) to a user-chosen `.txt` / `.in` via save dialog — pairs with **Import requirements**.
  - Settings fills the center without the Explorer/side panel beside it, and the header no longer has a close **X** next to Save — leave via the gear, another rail icon, or any other navigation.
  - Unsaved changes prompts: leaving Settings with a dirty draft asks **Save / Discard / Cancel**; quitting the app with dirty editor tabs and/or unsaved Settings asks **Save All / Don't Save / Cancel** (macOS no longer forces terminate past Dart’s `didRequestAppExit`). Closing a dirty tab also offers Save.

---

## Deferred

See `polish.md` → **Deferred**.

---

## Won't Fix (Beta)

See `polish.md` → **Won't Fix (Beta)**.

---

## In progress

- Publish the first **GitHub Release** zip so testers can follow the Install guide with no side channel.

---

## Smoke checklist (trust layer)

```
Create project → Create env → Run → Edit → Auto-save
→ Close → Reopen → Rename folder → Move folder
→ Delete env → Recreate env → Delete project → Recreate project
→ Run again → Quit (⌘Q) → Reopen → Recent Projects → Run again
```
