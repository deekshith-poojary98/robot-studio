# Robot Studio — Frontend

Flutter **desktop** UI for Robot Studio (macOS / Linux / Windows). The app talks to the local Python backend through `TransportGateway` (REST + WebSocket today).

Repo overview and backend setup: [../README.md](../README.md)  
Architecture: [../ARCHITECTURE.md](../ARCHITECTURE.md)  
Integration tests: [integration_test/README.md](./integration_test/README.md)

---

## Prerequisites

- Flutter 3.x with desktop support enabled
- Backend running at `http://127.0.0.1:8765` (see root README), unless you override the URL for tests
- Native deps for the bottom-panel Terminal: `xterm` + `flutter_pty` (FFI plugin — a **full rebuild/restart** is required after adding or changing them, and after entitlement edits)

---

## Run (development)

From the repo root (starts Flutter against a backend you already have on `:8765`):

```bash
make setup             # once
make backend           # terminal 1
make run               # terminal 2 — DEVICE defaults to macos|linux
```

Or manually:

```bash
cd frontend
flutter pub get
flutter run -d macos    # or linux / windows
```

On launch the shell health-checks the backend quietly in the background (connection chrome is not shown in the status bar). Day-to-day entry is **New Project** / **Open Project** (folder becomes its own `.robotstudio/` root). **Open/New Workspace** live under Advanced for multi-project containers.

### Packaged desktop (closed beta)

Testers download the zip from [GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases) and double-click — not `make backend` + `flutter run`. File bugs on GitHub Issues. Maintainers build from the repo root:

```bash
make package-macos     # → dist/macos/Robot Studio.app
make package-windows   # → dist/windows/RobotStudio/RobotStudio.exe (run on Windows)
make package-linux     # → dist/linux/RobotStudio/robot_studio (run on Linux)
```

Release builds embed a PyInstaller sidecar under `Contents/Resources/backend/` (macOS) or `backend/` next to the binary (Windows / Linux). `BackendHost` (`lib/core/backend_host.dart`) spawns it when `:8765` is not already healthy, waits on `/api/v1/health`, writes `~/.robot-studio/backend.pid`, and the native runner (macOS `applicationWillTerminate` / Windows `OnDestroy`) kills that PID on quit — Flutter `detached` alone is not reliable on desktop. Orphan sidecars from a previous crash are reclaimed via the pid file. App data stays in `~/.robot-studio` (settings, DB, pid file, and daily diagnostic logs under `logs/` — retained for 7 days).
---

## Layout

```
frontend/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── api/                 # Low-level HTTP helpers
│   │   ├── config/              # Backend URL / dart-defines
│   │   ├── gateway/             # TransportGateway + REST impl + DTOs
│   │   ├── logging/
│   │   └── theme/
│   └── presentation/
│       ├── shell/               # AppShell, status bar, controllers
│       ├── sidebar/             # Activity rail (Explorer, Tests, Git, …)
│       ├── toolbar/
│       ├── panels/              # Side + bottom panels (console, terminal, problems)
│       ├── workspace/           # Welcome, explorer
│       ├── editor/              # Robot code editor + language widgets
│       ├── execution/           # Run page + history
│       ├── reports/
│       ├── packages/
│       ├── environment/
│       ├── project/
│       ├── tests/               # Test Explorer panel
│       ├── git/
│       ├── plugins/
│       ├── search/
│       └── widgets/             # Shared UI (empty state, error dialog, guidance dialog, tree, badges, …)
├── test/                        # Widget / unit tests
└── integration_test/            # Live backend E2E suites
```

### Key concepts

| Piece | Role |
|-------|------|
| `TransportGateway` | UI contract for all backend calls |
| `RestTransportGateway` | Current implementation (injectable for tests) |
| `AppShell` | Top-level navigation, workspace lifecycle, run/git/package wiring |
| Shell controllers | Workspace / editor / execution state helpers |
| `showGuidanceDialog` | Actionable “next step” dialogs (open project, manage env, …) |
| `showFriendlyErrorDialog` | Plain-language failure dialogs; raw error behind **Show details** |
| `EmptyState` | One empty-state language app-wide (icon · title · why · one action; `compact` for the 280px rail) |

### Sidebar panels

Explorer · Search (Find in Files) · Insights · Libraries · Tests · Packages · Source Control · Reports · Doctor

Plugins remains fully implemented but is **hidden for beta** from the activity bar
(`SidebarPanel.plugins.showInActivityBar = false`) and the command palette until the
extension UX is ready. Restore the commented `plugins.open` palette item in
`app_shell.dart` when re-enabling.

AI and Settings are **not** in the rail until those features ship — nothing in the chrome
opens a “coming soon” surface. Only Explorer, Search, Tests, Libraries, and Reports own the 280px side rail;
Doctor is a main-view Project Health Center (no side rail list).

the other panels take over the main view, and the rail collapses instead of showing a
column that says “open in the main view”.

---

## UX notes (current)

- Desktop window minimum size is **1360×800** (macOS / Linux / Windows) so the IDE shell stays usable.
- Backend health: probes on launch, then every **2s while offline** and **15s while connected**. A single failed probe is ignored; **3 consecutive failures** mark the backend offline and reconnect the stream when it recovers. Health traffic is logged at debug only. While offline, the status bar shows **BACKEND UNAVAILABLE** (not CONNECTED/OFFLINE), and the welcome screen shows a short start-backend hint.
- Toolbar: left = project chip (name only) / environment / branch (git Fetch·Pull·Push live in a ⋯ menu, repos only); center = command search (⌘⇧P / Ctrl+Shift+P; ⌘K / Ctrl+K still works); right = **run configuration** selector (`Default` until one is chosen) immediately before one attached, equal-width **Run / Project / Stop** segmented control (Run primary, Stop red only while running). The selector does not change Run vs Project semantics or the active toolbar environment; New/Edit/Manage are dialogs (Duplicate is first-class in Manage). Configurations persist at `{project}/.robotstudio/run-configurations.json`. The environment chip stays clickable when it shows **No environment** (Create Environment… / Manage Environments…) so dismissing the missing-env toast does not leave users stuck. No product wordmark (the rail logo carries it), no profile or notification icons. Popup / context menus use compact 28px rows (not Material’s default 48px).
- **Window menu bar** (native `PlatformMenuBar`, VS Code–style): **File** (New/Open Project·Workspace, Save/Save All, **Settings…** ⌘,, Close/Reopen Editor, Reveal in Finder) · **Edit** (Find/Replace, Find in Project, Format, Word Wrap) · **View** (Command Palette, Go to File, Explorer/Search/Symbols/Source Control/Tests/Reports/Robot Doctor/Problems, Toggle Side Bar/Terminal) · **Go** (Definition, Peek, References, Symbols, Hover) · **Run** (Run File **F5** / Project / Stop **Shift+F5**) · **Terminal** (Toggle). **Robot Doctor** uses **⌘⇧D** / **Ctrl+Shift+D**. On macOS the first menu is the **Robot Studio** app menu (About / Hide / Quit). Menu accelerators own those chords — Flutter `Shortcuts` only keeps Ctrl+Tab editor cycling so keys don’t double-fire.
- **Settings** is a **full center screen** (`PreferencesPage`), not a dialog, so categories can grow. Editor **Font Family** lists **monospace fonts installed on the machine** (they are not bundled; Menlo is the only built-in default). Reachable from the **gear at the bottom of the sidebar rail** (highlighted while open), File → **Settings…** ⌘,, or the command palette — and it opens with no project loaded, outranking the welcome screen. Left rail lists categories (Editor · Execution · Search · Appearance); the header carries **Restore Defaults / Discard / Save** plus an unsaved-changes line. Save and Discard stay disabled until the draft differs from the stored settings. The page **listens to `AppSettingsController`**, so a setting changed elsewhere (Edit ▸ Word Wrap, palette, any `patch`) lands on the open page instead of going stale and being written back on Save; it three-way merges, keeping fields you are mid-edit. Any explicit navigation (opening a file, a rail panel, a run) leaves the screen. Typed `SettingsService` owns `~/.robot-studio/settings.json`; live updates, no config-file editor. Appearance includes **Restore Last Project** (default on): cold start reopens the most recent project, or recent workspace if none, and soft-fails to welcome when the path is gone — editor tabs are not restored yet. Appearance also includes **Accent** (Teal default plus Electric Blue, Purple, Mint, Warm Orange, Soft Gold, Coral, Crimson, Burnt Amber, Slate): Save republishes the colour to `MaterialApp` so the whole chrome updates.
- Editor chrome is tabs + breadcrumb only (no action strip under the breadcrumb). Save / Format / Find / word-wrap / Go to Definition / etc. live in the window menu bar (and keyboard shortcuts / command palette).
- Bottom panel tabs are Terminal · Problems. Run output lives on the **Tests** view (not a duplicate Execution Logs / Console tab). Terminal opens an interactive login shell (`xterm` + `flutter_pty`) in the project folder on desktop (restart/kill from the tab chrome). The macOS build runs **without App Sandbox** (`macos/Runner/*.entitlements`) — with the sandbox on, the shell cannot be spawned and the tab only prints `[process exited with code 255]`. Changing entitlements needs a full rebuild, not hot reload.
- Welcome: centered wordmark + tagline, then **New Project** / **Open Project** and **Recent Projects**; **Open/New Workspace** + **Recent Workspaces** under Advanced. When the backend is unreachable, a quiet **Backend unavailable** banner appears under the tagline (release: reopen/reinstall; debug: `make backend`). New Project asks for a name plus a **Location** (prefilled beside the current project, editable, with **Browse…**) — no Browser/API/Selenium template picker; the project gets empty `tests/` / `resources/` / `variables/` folders and a seeded `.gitignore` that ignores `.robotstudio/` (Studio envs + reports live under it) and common Python noise. Opening a project initializes `.robotstudio/` in-place (no wrapper dirs) and does not block on environment creation. Folders that don’t look like Robot projects show a warning with **Continue anyways** (opens via `force=true`) instead of a hard block. Missing-env prompts and short notifications appear as dark **bottom-right** toasts (not a white bottom banner). **Recent Workspaces** only lists classic multi-project containers (with a `Projects/` folder) — in-project opens stay under **Recent Projects**.
- Opening a workspace/project auto-selects a recent/first project when possible; **Recent Projects** and command palette **Open Project** use `POST /projects/open-path`. **New Project** means the same thing everywhere (welcome, **File → New Project…**, Explorer project-header `+`, palette, guidance dialogs): one dialog collects the name and parent folder (no folder picker opens up front — that read as "open existing"), then Studio creates a standalone project via `POST /projects/standalone` and **opens it fresh** — editor tabs, file tree, and git state reset to the new project. It never nests the new project inside whatever was open. Adding a project to a classic multi-project container is the separate palette command **New Project in Workspace** (`POST /projects`, keeps the container open and just selects the new project). Indexing and git refresh run in the background after open (status shows “Indexing…”). Explorer uses a VS Code-style **lazy file tree**: root loads depth 0 (immediate children), folders expand via follow-up `GET /files/tree?path=…&depth=0`, and the UI renders a virtualized flat list (`ListView.builder`) so only visible rows are built. Dotfiles like `.gitignore` are shown; heavy/noise entries (`.git`, `.venv`, `node_modules`, `.DS_Store`, …) stay hidden. `.robotstudio/` is browsable **in full** — `environments/` and `reports/` expand like any other folder, and no filter applies inside it (lazy expand keeps that cheap). Switching to Environments / Packages / Search / etc. keeps the active project selected so Run still works after creating an env. If the active env’s Python folder was deleted, the toolbar shows `venv · missing` (still “active” in metadata), **Run** / **Run Project** stay disabled with a recreate tooltip, and run handlers guide you to Manage Environments instead of starting a doomed execution.
- **No host Python:** before offering Create Environment, Studio probes `GET /environments/interpreters`. If none are found, the bottom-right toast becomes **Python is not installed** with **How to Install** (platform-specific `brew` / python.org / apt guidance) and **Select Existing…**. If that probe throws (transport error), the toast becomes **Could not detect Python** with install / create / select actions (no “start the backend” wording). The Create Environment dialog uses the same compact form spacing, 18px title, aligned 36px actions, and left-aligned checkbox as New Project; it shows the same warning + **Refresh** when discovery is empty. Create-from-toast installs Robot Framework by default (matching the dialog) and opens the install guide when discovery is empty. Pip/venv subprocesses use a stable working directory so a deleted backend cwd cannot crash `os.getcwd()` during Create Environment; install failures show “Could not install Robot Framework…” (not a false “RF missing from active environment”).
- **Package Manager requirements:** **Import requirements** uses the native file picker for `.txt` / `.in`, asks for confirmation because pinned versions can upgrade or downgrade the active environment, then calls `POST /packages/install-requirements`. **Export requirements** saves a `pip freeze` of the active environment via `POST /packages/export-requirements` (native save dialog, `.txt` / `.in`). The sidecar never uses host Python. The package list and Robot Framework status refresh after import/export.
- **Package search** (**Search installed** and PyPI results) accepts partial matches and ranks **exact → prefix → substring → fuzzy** (ordered subsequence, ≥2 chars, must start at a token boundary). Hyphen/underscore/dot are normalized; ordering is deterministic — no typo engine. PyPI discovery uses the public Simple API name index (cached under `~/.robot-studio/cache/`, refreshed daily) because Warehouse HTML search is bot-gated; the dialog shows the **top 20** ranked hits with versions/summaries from the JSON project API. Installing a version that is already present offers **Cancel** / **Force Install** (`pip --force-reinstall`).
- Explorer file ops (context menu + project-header New File/Folder + shortcuts when the tree is focused): **New File** / **New Folder** (inline name entry; names without an extension get `.robot` appended on submit), **Rename** (F2, inline; case-only renames like `libs` → `Libs` work on macOS), **Delete** (confirmation), **Duplicate**, **Copy Relative/Absolute Path**, **Reveal in Finder/Explorer/File Manager**, and drag-and-drop move. **Multi-select**: ⌘/Ctrl-click toggles, Shift-click selects a range; right-click keeps the selection and offers **Delete N Items** / **Copy … Paths**; click outside the tree (or Esc / empty explorer space) clears the selection so New File/Folder targets the project root again; header New File/Folder keep the current folder selection; drag-drop moves the whole pruned selection (a selected parent drops nested children from the batch). New `*.robot` files open with a full suite scaffold (`Settings` / `Variables` / `Test Cases` / `Keywords` + example test & keyword); other extensions stay empty. Mutations go through `FileService` → EventBus → `/workspace/events` (no full tree rebuild).
- Explorer is file-focused (project header + file tree). File/folder rows use VS Code **Material Icon Theme** glyphs via `vscode_material_icon_theme` (`fileToIcon` / `directoryToIcon`; `.resource` → Robot glyph). A collapsible **OUTLINE** pane sits under the tree (VS Code-style; collapsed by default) for the active editor’s **DocumentSymbolTree** — nested Settings / Variables / Keywords / Tests with calls and control structures, filter box, and caret-driven active highlight. Breadcrumbs are clickable; folding ranges come from the same tree. Environments, Packages, and Reports live on their dedicated activity-rail views / toolbar — not duplicated under Explorer.
- **Run** is the primary segment in the attached **Run / Project / Stop** toolbar control; Project stays quiet and Stop stays muted when idle. **Run** targets the active `.robot` editor (or the last selected suite when no editor is focused) — never a non-robot file and never a silent fallback to “first suite in the project.” Starting a run brings the **Execution** monitor to the front; Jump to Source brings the editor forward. The **Tests** center view is monitoring-only (live output + recent runs + Failed Tests + status) — it does not duplicate Run File / Run Project / Stop; launch from the toolbar, F5 / Shift+F5, Test Explorer tree actions, menus, or the command palette. When a run has failures, a **Failed Tests** section lists each one with message, **Jump to Source**, and **Re-run Test**. Passing runs and Robot errors with zero failed tests (no matching tags, empty suite) skip that block — no loading skeleton above Live Output. Reports badges follow the same rule: **FAIL** only when tests failed; empty selection is **NO TESTS**.
- Run status badge shows `Last: Failed` (etc.) and opens **Tests**; Idle badge is hidden.
- Status bar shows the active **project** name on the left (`NO PROJECT` when none); `ROBOT` / `PYTHON` from the active environment (full `major.minor.micro`) sit flush on the right. Version slots are hidden rather than showing `—`; long project/file names ellipsize instead of overflowing. Connected backend state stays quiet; **BACKEND UNAVAILABLE** appears on the right only while offline. Ephemeral live-workspace hints appear mid-bar (`Indexing workspace…`, `Workspace synchronized`, external change counts). Decorative UTF-8/LF chips were removed; ERRORS/WARNINGS/project chips have tooltips.
- Editor: syntax highlighting via `re_highlight` for common file types (Python, JSON, YAML, JS/TS, Markdown, …) using builtin grammars; `.robot` / `.resource` use a custom Robot Framework grammar. Dark uses VS Code **Dark+** (sky-blue sections/variables, teal keyword calls, magenta settings, yellow test names); light switches to **Light+** equivalents (`codeThemeForPath(path, palette)` → `robotHighlightTheme(brightness)`), because Dark+ hues are unreadable on white.
- **Theming.** Colour tokens live in `AppPalette` (`core/theme/app_palette.dart`), a `ThemeExtension` with `dark` and `light` variants, read in widgets as `context.palette`. Text fields inherit `textTheme.bodyLarge` at **13px** (same as body copy) so dialogs are not Material’s 16px default. Going through `Theme.of` is deliberate: it gives every reader an InheritedWidget dependency, so a theme switch repaints even `const` widgets — a mutable global would leave them stale. `buildAppTheme(palette)` builds **both** brightnesses from one function; deriving light via `copyWith` of dark is what previously left near-white text on light surfaces. The theme is applied on `MaterialApp` (`theme` / `darkTheme` / `themeMode`) and Appearance preferences (theme mode + accent) are published up from `AppShell` via `ValueNotifier`s, so dialogs, popup menus and the shell all follow them and `system` tracks the OS. Accent colours are curated in `app_accent.dart` (`AppPalette.forAccent`); Teal matches the stock palettes. `AppColors` still exists for `const`/context-free spots but is unused in `lib/` — prefer the palette. Note that `MaterialApp` lerps theme changes over ~200ms, so tests must settle before sampling colours.
- Find / Replace (⌘/Ctrl+F, ⌘/Ctrl+H, **Edit → Find/Replace**, or the command palette): a floating box docked to the **top-right of the editor** — `Aa` match case, `ab` match whole word, `.*` regex, match counter, prev/next, Enter / ⇧Enter to step through matches, Esc to close. Whole-word wraps the query in `\b…\b` under the hood (and combines with regex as `\b(?:…)\b`); the field still shows the raw query. re_editor stacks the find widget as a non-positioned `Stack` child, so `EditorFindPanel` must size itself; an expanding root would paint over the whole document.
- Explorer stays synchronized via `/api/v1/workspace/events` (incremental parent refresh — expanded folders and selection are preserved). Open editors detect external modify/delete without polling. File rows highlight the active editor path; long names truncate to one line; expand chevrons animate (~160ms). Hovering a file/folder name shows a home-relative path tip (`~/Desktop/OrangeHRM/tests/…`) after a short delay (~700ms) on **every** row — Material’s shared tooltip would skip the wait when hopping between items; Explorer uses `AlwaysDelayedTooltip` instead. The Explorer / Tests / Reports side column is drag-resizable (200–480px, default 280).
- **Externally deleted project/workspace**: deleting the open folder in Finder emits no filesystem-watcher events (the watcher loses the very directory it observes), so the backend also polls the roots every ~2s and sends `WORKSPACE_CHANGED` / `PROJECT_CHANGED` with `reason: "missing"`. The app then shows **Workspace/Project no longer exists** (Dismiss / Locate / Close) — a missing workspace suppresses the project event so standalone projects raise one dialog, not two. Detecting a missing workspace also purges that workspace’s environment and execution-run registry rows in `~/.robot-studio/robot-studio.db` as artifact hygiene. Identity itself is a durable UUID in `.robotstudio/workspace.json` (standalone: same value as `project.json`); move/rename keeps the id and updates the stored path. Delete-and-recreate at the same path mints a new id — so ghost `venv · missing` chips and stale Reports history do not survive. If you dismiss the dialog and save anyway, the backend refuses the write (`no longer on disk`, mapped to plain copy by `friendlyErrorSummary`) instead of silently recreating the folder from the file you saved.
- Empty states use shared `EmptyState` across explorer/files, Source Control, Find in Files, Symbols, Problems, Tests, Environments, and Plugins. List loads use `SkeletonList` instead of a bare spinner where practical.
- Errors use `showFriendlyErrorDialog` / `showContinueAnywayDialog`: a plain summary, a suggested fix, and **Show details** for the raw exception (with Copy details). Common backend/OS messages (`Path does not exist`, missing project, Git, env, permissions, timeouts, `ensurepip` / `python3-venv` / failed venv create, …) map to specific copy; otherwise a cleaned backend detail is shown instead of a blank “That action did not finish.” Timeouts say “taking longer than expected.” Dialog widths come from `AppDialogWidth.form` (420) / `AppDialogWidth.wide` (480).
- Editor notices (the strip under the breadcrumb: `Saved login.robot`, `Formatted document`, `Copied relative path`, `No references found…`) auto-expire after **4s** and carry a × to dismiss early — the strip pushes editor content down, so it never stays parked. Set them via `EditorShellController.setStatusMessage`, not by assigning `statusMessage`.
- Editor tabs: hover highlight, full-path tooltip, Semantics on close. Right-click a tab for Close / Close Others / Close All / Close Saved / Close to the Right, plus Reveal in Finder/Explorer and Copy Relative/Absolute Path.
- Git action rows (source control header, commit bar) wrap instead of scrolling horizontally, so nothing hides off-screen on small windows. Source Control is always scoped to the **open project** (shows repository root when present); nested projects under a parent monorepo show "No Git repository in this project" with Init in this project — never the parent repo unless that folder is opened as the project. Lists untracked new files (not only modified tracked ones); paths ignored by `.gitignore` stay hidden. The loading skeleton mirrors the real layout (changes + commit | history) and only appears on first load — refreshes keep the current content.
- Activity rail: selected/hover highlight uses square corners (no rounded pill).
- Activity rail tooltips describe each panel (e.g. Reports — run history and HTML reports).
- Plugin rows show **Enable** or **Disable** (not both); built-ins don’t offer a disabled Enable control.
- Reports: rail panel **Runs** lists recent runs by run number from `.robotstudio/reports/Run-*` (e.g. `Run 20260101-120000 · FAIL`; tap to open details); main Reports page shows dashboard + details only (no duplicate run list). Artifact filenames are hyperlinks; Reveal Folder remains.
- **Robot Doctor**: structural project scanner (`DoctorPage`) — circular imports, duplicate keywords, potentially unused keywords/resources. Single **Scan project** action (no Quick/Default/Full). Findings expand to why-it-matters, cycle path, affected files, and **Open source**. Missing imports stay in Problems; run-health smells stay in Insights/Reports. Backed by `/api/v1/doctor/*`.
- **Insights**: run-health triage first (last run, fail streak, flaky files, failure mix, Files table) into Reports / editor / rerun; composition stays secondary index context. No extra charts.
- External file conflicts offer **Reload** / **Keep Mine** only (no unfinished Compare).
- When a run finishes, the IDE **stays on the current view** and shows a toast with **View Report** — it does not auto-navigate to Reports.
- Run / Run Project stay disabled until Robot Framework is installed in the active environment (tooltip explains why).
- Problems: live diagnostics while editing; Analysis Engine missing imports share Doctor's `missing_import` inspection id (shown in the Problems subtitle as `analysis · missing_import`); click a problem (or status-bar ERRORS/WARNINGS) to jump to file:line:column; panel auto-opens when issues appear. The list updates in place while typing — no skeleton flash on every keystroke. Local settings like `[Documentation]` / `[Tags]` are not flagged as unknown keywords. Continuation (`...`), RF automatic variables (`${TRUE}` / `${FALSE}` / …), number variables (`${10}` / `${3.14}` / `${0xFF}`), and variables from `FOR` / `VAR` / `[Arguments]` / assignments are recognized. Missing `Resource` / `Variables` imports are checked on disk and unified with Analysis findings. `Library` imports and their keywords are resolved from the **active environment** (via Robot libdoc), not only the workspace file index — so packages installed in the project venv (e.g. `robotframework-excelsage` → `ExcelSage`) are recognized.
- Indexing / analysis progress: live `INDEX_PROGRESS` and `ANALYSIS_PROGRESS` events update the status bar and show a soft non-blocking overlay so long rebuilds never look like a frozen IDE.
- Go to Definition (F12 / Ctrl+Click): sends file/line/column/content so the backend can resolve the Robot cell under the caret; falls back to the Analysis Engine semantic graph; when multiple definitions exist, a picker lists every match.
- Completions use a **CompletionProvider pipeline** (buffer symbols, variables, keywords/libdoc, named arguments, RF DSL, index, files) with **usage-based ranking** and **context-aware filtering**. After a resolved keyword call, argument context offers ranked `name=` inserts at a 2-space separator (skipping parameters already present; not while typing the current value). Completions and highlighting separate **RF DSL** (section headers, suite/local settings, `IF`/`FOR`/`TRY`/`VAR`/… — kind `dsl`) from **BuiltIn library** keywords (`Log`, `Should Be Equal`, … — kind `keyword`, detail BuiltIn). Keywords from `Library` imports in the open file are suggested from the **active environment** (libdoc); `WITH NAME` aliases suggest `Alias.Keyword` forms. Popup matching is case-insensitive **prefix / word-start** (typing `A` matches `Add Two Numbers`, not every snippet that happens to contain the letter `a`). Accepting a completion records usage so frequently chosen items rise in future suggestions.
- **Parameter authoring:** caret-driven signature card (and pointer hover) shows parameter order, defaults, required vs optional, and the active parameter while typing. ESC dismisses. Shared source-agnostic `KeywordMetadata` backs signature help, named args, and hover.
- **Libraries** side rail (View → Libraries): browse BuiltIn + imported libraries, search keywords, read docs/arguments, Jump to source when available. Filtering lives in `LibraryExplorerController`. Keyword detail uses the complete Libdoc `kw.doc` (never the truncated `short_doc`) and renders it as selectable rich text — headings, paragraphs, lists, tables, inline emphasis/code, and preformatted examples — preserving unknown syntax verbatim.
  - Both documentation dialects are supported: **Robot Framework markup** and **Markdown**. `RobotDocumentation` picks one from libdoc's `doc_format` (a library's `ROBOT_LIBRARY_DOC_FORMAT`), which flows through `KeywordMetadata.doc_format` to `LibraryKeywordInfo.docFormat`. Since libdoc defaults that field to `ROBOT`, an undeclared `ROBOT` is **sniffed** (Markdown-only markers scored against Robot-only markers) so libraries that write Markdown without declaring it still render correctly; an explicitly declared format always wins. `TEXT` / `REST` render verbatim and `HTML` is normalised to Robot markup.
  - Robot markup follows libdoc's own `htmlformatters` rules: `| ` marks a preformatted block and the marker is stripped, `| a | b |` (closing pipe) is a table with `=Header=` cells, ` ``code`` ` is inline code while a single backtick is a keyword link, `*bold*` / `_italic_` honour word boundaries, `- ` is the only bullet marker, and paragraph lines wrap rather than breaking at source newlines.
- Hover tooltip (VS Code-style): rest the pointer on a keyword call and a floating card appears near the cursor with argument chips + short docs from the **active environment** (Robot libdoc). Moves away / click dismisses it — no bottom-left signature chip.
- Command palette: toolbar search / ⌘⇧P / Ctrl+Shift+P (also ⌘P / Ctrl+P quick-open, ⌘K / Ctrl+K) opens commands + file/symbol search. Sidebar **Search** (or **Edit → Find in Project** / ⌘⇧F / Ctrl+Shift+F) opens **Find in Files** in the left rail while keeping the editor mounted; matches can show enclosing test/keyword/variable labels from the index. **View → Symbols** (or palette **Symbols**) opens the indexed symbol search page (filter by kind).
- **Keyboard shortcuts** (VS Code–aligned where the product supports them):
  - **Window menu bar** owns most chrome chords (Save, Save All, Close, Reopen, Toggle Side Bar/Terminal, Find in Project, Format, Problems, Command Palette / Go to File, **F5** Run File, **Shift+F5** Stop, **⌘/Ctrl+Shift+D** Robot Doctor) so they don’t double-fire with Flutter `Shortcuts`.
  - **Flutter Shortcuts** still handle Ctrl+Tab / Ctrl+⇧Tab editor cycling.
  - **Editor** (re_editor + Robot overrides): ⌘/Ctrl+F find · ⌘/Ctrl+H replace · ⌘/Ctrl+/ comment · ⌥/Alt+↑↓ move line · ⇧⌥/Alt+↑↓ copy line · ⌘/Ctrl+⇧K delete line · F12 go to definition · undo/redo. Split editor / multi-cursor / Settings are not shipped yet.
- **Test Explorer** (Tests rail): lazy suite expand (children load on demand) + virtualized rows; PASS/FAIL/SKIP/NOT RUN/RUNNING; toolbar Run All / Run Current File / Run Failed / Refresh / Expand / Collapse; confirms before large project runs (threshold default 100, backend-enforced via 409); live filter by suite, test, tag, or file. Single-project / standalone opens hide the redundant workspace container row (workspace + project often share the same folder name) and start at the project; multi-project workspaces still show the workspace root.
- Missing Robot Framework blocks Run with an Install / Choose Environment dialog (no empty 17ms “failed” runs). Missing-library run failures (Browser, SeleniumLibrary, …) can prompt Install via snackbar.

---

## Tests

### Widget / unit

```bash
# From repository root
make test-frontend
make analyze
# or:
cd frontend
flutter test
flutter analyze
```

Notable suites under `test/`:

| File | Covers |
|------|--------|
| `editor_tabs_context_menu_test.dart` | Editor tab right-click Close/Others/All/Saved/Right + path actions |
| `find_in_files_panel_test.dart` | Find in Files rail: auto-expand single-file hits, remember expansion |
| `widget_test.dart` | Welcome, dialogs, managers, toolbar, editor shells, Symbols page |
| `editor_syntax_test.dart` | File-extension → re_highlight / custom Robot theme mapping |
| `editor_trust_fixes_test.dart` | Section completion prefix replace; Documentation vs IF/FOR highlighting |
| `app_menu_bar_test.dart` | Native File/Edit/View/Go/Run/Terminal menus; Save disabled with no file |
| `python_missing_guidance_test.dart` | No-Python toast / Create Environment banner / install recovery copy |
| `editor_find_panel_test.dart` | Find/Replace box stays a floating top-right widget (never covers the code), replace row, Esc closes, whole-word wraps `\b…\b` |
| `editor_status_notice_test.dart` | Editor notices auto-expire, newest wins, × dismisses early |
| `virtual_file_tree_test.dart` | Virtualized explorer, multi-select, context menus, inline rename, silent `.robot` append, shortcuts |
| `side_panel_resize_test.dart` | Side panel drag resize handle + width clamps |
| `always_delayed_tooltip_test.dart` | Path tip waits on every Explorer hover (no Material skip) |
| `explorer_file_icon_test.dart` | Material Icon Theme file/folder glyphs |
| `test_explorer_panel_test.dart` | Test Explorer tree, search, toolbar, expand/status |
| `status_bar_test.dart` | ROBOT / PYTHON labels, project name, hidden version slots |
| `ux_guidance_test.dart` | Guidance dialog + recent-item tooltips |
| `execution_page_test.dart` | Tests/Execution center view is monitoring-only (no duplicate Run/Stop) |
| `failed_tests_panel_test.dart` | Failed Tests Jump / Re-run actions; hidden while run is active |
| `ux_polish_ab_test.dart` | Status bar omits connection chrome; Run/Stop styling, Last: run badge, report hyperlink |
| `workspace_live_events_test.dart` | Workspace event parsing (incl. INDEX_PROGRESS), StatusBar notification slot, Git debounce, progress busy flags |
| `beta_hardening_test.dart` | Large-run GatewayException fields, multi-definition JSON, analysis DiagnosticInfo, Robot cell token extract |
| `execution_stream_status_test.dart` | Cold-start idle vs stale run status |
| `reports_side_panel_test.dart` | Reports side panel uses real runs |
| `doctor_page_test.dart` | Robot Doctor health summary, findings, jump-to-source |
| `git_widget_test.dart` | Source control widgets |
| `problems_panel_test.dart` | Problems list empty state + click |
| `editor_shortcuts_test.dart` | Shell + editor shortcut activator maps (VS Code chords) |
| `terminal_toggle_shortcut_test.dart` | ⌘` / Ctrl+` toggle token opens then collapses Terminal |
| `problems_loop_test.dart` | Reveal Problems tab, status-bar ERRORS shortcut, location labels |
| `terminal_panel_test.dart` | Terminal tab empty state without a project |
| `command_palette_test.dart` | Palette filter, Enter activate, workspace file results |
| `backend_health_retry_test.dart` | Health probe retries; transient failures ignored; offline after consecutive misses |
| `plugin_manager_test.dart` | Plugin manager layout / rows |
| `ux_polish_sprint_test.dart` | Error dialog Show details, env toast copy, deleted-root copy, collapsed rail, bottom tabs, hidden Settings |
| `ux_polish_pre_m14_test.dart` | Skeleton loaders, EmptyState semantics, explorer selection, status bar tooltips, timeout copy |

### Integration (E2E)

Prefer the repo script so macOS sandbox can reach Python:

```bash
# From repository root
make test-integration
make test-integration SUITE=startup_test.dart
# or:
./scripts/run_integration_tests.sh
./scripts/run_integration_tests.sh startup_test.dart
```

Full suite list and harness: [integration_test/README.md](./integration_test/README.md).

---

## Configuration (dart-define)

Used mainly by integration tests / harness:

| Define | Purpose |
|--------|---------|
| `INTEGRATION_BACKEND_URL` | Backend base URL |
| `ROBOT_STUDIO_BACKEND_PORT` | Port paired with the test backend |
| `ROBOT_STUDIO_REPO_ROOT` | Repo root for fixtures / scripted backend |

Default desktop runs use `http://127.0.0.1:8765` via app config.

---

## Keeping docs in sync

When you change frontend behavior, setup, or tests, update:

1. [../README.md](../README.md)
2. This file (`frontend/README.md`)
3. [integration_test/README.md](./integration_test/README.md)
