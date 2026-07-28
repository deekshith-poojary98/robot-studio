# Robot Studio — Frontend

Flutter **desktop** UI for Robot Studio (macOS / Linux / Windows). The app talks to the local Python backend through `TransportGateway` (REST + WebSocket today).

Repo overview and backend setup: [../README.md](../README.md)  
Architecture: [../ARCHITECTURE.md](../ARCHITECTURE.md)  
Integration tests: [integration_test/README.md](./integration_test/README.md)

---

## Prerequisites

- Flutter 3.x with desktop support enabled
- Backend running at `http://127.0.0.1:8765` (see root README), unless you override the URL for tests

---

## Run

```bash
cd frontend
flutter pub get
flutter run -d macos    # or linux / windows
```

On launch the shell health-checks the backend quietly in the background (connection chrome is not shown in the status bar). Day-to-day entry is **New Project** / **Open Project** (folder becomes its own `.robotstudio/` root). **Open/New Workspace** live under Advanced for multi-project containers.

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
│       ├── panels/              # Side + bottom panels (console, logs, problems)
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

Explorer · Search · Tests · Packages · Plugins · Source Control · Reports

AI and Settings are **not** in the rail until those features ship — nothing in the chrome
opens a “coming soon” surface. Only Explorer, Tests, and Reports own the 280px side rail;
the other panels take over the main view, and the rail collapses instead of showing a
column that says “open in the main view”.

---

## UX notes (current)

- Desktop window minimum size is **1280×720** (macOS / Linux / Windows) so the IDE shell stays usable.
- Backend health: probes on launch, then every **2s while offline** and **15s while connected**. A single failed probe is ignored; **3 consecutive failures** mark the backend offline and reconnect the stream when it recovers. Health traffic is logged at debug only — the status bar does not show CONNECTED/OFFLINE.
- Toolbar: left = project chip (name only) / environment / branch (git Fetch·Pull·Push live in a ⋯ menu, repos only); center = command search (⌘K on macOS, Ctrl+K elsewhere); right = **Run** (labelled, primary) plus icon-only **Run Project** and **Stop**. No product wordmark (the rail logo carries it), no profile or notification icons. Popup / context menus use compact 28px rows (not Material’s default 48px).
- Editor strip: Save · Save All · Format · Find on the left, word-wrap toggle and a ⋯ menu on the right. Replace, Format Selection, Go to Definition, Peek Definition, Find References, Hover Info, Go to Symbol in File, Find Symbol in Project, and Reveal in Folder live in that menu instead of a permanent ribbon.
- Bottom panel tabs are Console · Execution Logs · Problems only; the Output and Terminal stubs were removed.
- Welcome: **New Project** + **Open Project** + **Recent Projects** first; **Open/New Workspace** + **Recent Workspaces** under Advanced. New Project asks only for a name (empty `tests/` / `resources/` / `variables/` folders — no Browser/API/Selenium template picker). Opening a project initializes `.robotstudio/` in-place (no wrapper dirs) and does not block on environment creation. Folders that don’t look like Robot projects show a warning with **Continue anyways** (opens via `force=true`) instead of a hard block. Missing-env prompts and short notifications appear as dark **bottom-right** toasts (not a white bottom banner). **Recent Workspaces** only lists classic multi-project containers (with a `Projects/` folder) — in-project opens stay under **Recent Projects**.
- Opening a workspace/project auto-selects a recent/first project when possible; **Recent Projects** and command palette **Open Project** use `POST /projects/open-path`. **New Project** from welcome uses `POST /projects/standalone`. Indexing and git refresh run in the background after open (status shows “Indexing…”). Explorer uses a VS Code-style **lazy file tree**: root loads depth 0 (immediate children), folders expand via follow-up `GET /files/tree?path=…&depth=0`, and the UI renders a virtualized flat list (`ListView.builder`) so only visible rows are built. Dotfiles like `.gitignore` are shown; heavy/noise entries (`.git`, `.venv`, `node_modules`, `.DS_Store`, …) stay hidden. Switching to Environments / Packages / Search / etc. keeps the active project selected so Run still works after creating an env. If the active env’s Python folder was deleted, the toolbar shows `venv · missing` (still “active” in metadata) instead of looking healthy.
- Explorer file ops (context menu + project-header New File/Folder + shortcuts when the tree is focused): **New File** / **New Folder** (inline name entry; names without an extension get `.robot` appended on submit), **Rename** (F2, inline), **Delete** (confirmation), **Duplicate**, **Copy Relative/Absolute Path**, **Reveal in Finder/Explorer/File Manager**, and drag-and-drop move. New `*.robot` files open with a full suite scaffold (`Settings` / `Variables` / `Test Cases` / `Keywords` + example test & keyword); other extensions stay empty. Mutations go through `FileService` → EventBus → `/workspace/events` (no full tree rebuild).
- Explorer is file-focused (project header + file tree). File/folder rows use VS Code **Material Icon Theme** glyphs via `vscode_material_icon_theme` (`fileToIcon` / `directoryToIcon`; `.resource` → Robot glyph). A collapsible **OUTLINE** pane sits under the tree (VS Code-style; collapsed by default) for the active editor’s document symbols. Environments, Packages, and Reports live on their dedicated activity-rail views / toolbar — not duplicated under Explorer.
- **Run** is the only primary-styled run control; **Run Project** and **Stop** are quiet icon buttons (Stop stays muted when idle).
- Run status badge shows `Last: Failed` (etc.) and opens **Execution Logs**; Idle badge is hidden.
- Status bar shows the active **project** name on the left (`NO PROJECT` when none); `ROBOT` / `PYTHON` from the active environment (full `major.minor.micro`) sit flush on the right. Version slots are hidden rather than showing `—`; long project/file names ellipsize instead of overflowing. Backend connection state is not displayed. Ephemeral live-workspace hints appear mid-bar (`Indexing workspace…`, `Workspace synchronized`, external change counts). Decorative UTF-8/LF chips were removed; ERRORS/WARNINGS/project chips have tooltips.
- Editor: syntax highlighting via `re_highlight` for common file types (Python, JSON, YAML, JS/TS, Markdown, …) using builtin grammars; `.robot` / `.resource` keep the custom Robot Framework grammar.
- Explorer stays synchronized via `/api/v1/workspace/events` (incremental parent refresh — expanded folders and selection are preserved). Open editors detect external modify/delete without polling. File rows highlight the active editor path; long names truncate to one line; expand chevrons animate (~160ms). The Explorer / Tests / Reports side column is drag-resizable (200–480px, default 280).
- Empty states use shared `EmptyState` across explorer/files, Source Control, Search, Problems, Tests, Environments, and Plugins. List loads use `SkeletonList` instead of a bare spinner where practical.
- Errors use `showFriendlyErrorDialog`: a plain sentence, a suggested fix, and **Show details** for the raw exception (with Copy details). Timeouts say “taking longer than expected” rather than dumping `TimeoutException`. Dialog widths come from `AppDialogWidth.form` (420) / `AppDialogWidth.wide` (480).
- Editor tabs: hover highlight, full-path tooltip, Semantics on close. Right-click a tab for Close / Close Others / Close All / Close Saved / Close to the Right, plus Reveal in Finder/Explorer and Copy Relative/Absolute Path.
- Git action rows (source control header, commit bar) wrap instead of scrolling horizontally, so nothing hides off-screen on small windows. Source Control lists untracked new files (not only modified tracked ones); paths ignored by `.gitignore` stay hidden. The loading skeleton mirrors the real layout (changes + commit | history) and only appears on first load — refreshes keep the current content.
- Activity rail: selected/hover highlight uses square corners (no rounded pill).
- Activity rail tooltips describe each panel (e.g. Reports — run history and HTML reports).
- Plugin rows show **Enable** or **Disable** (not both); built-ins don’t offer a disabled Enable control.
- Reports: rail panel lists recent runs (tap to open details); main Reports page shows dashboard + details only (no duplicate run list). Artifact filenames are hyperlinks; Reveal Folder remains.
- Problems: live diagnostics while editing; click a problem (or status-bar ERRORS/WARNINGS) to jump to file:line:column; panel auto-opens when issues appear. Local settings like `[Documentation]` / `[Tags]` are not flagged as unknown keywords.
- Command palette: toolbar search / ⌘K / Ctrl+K opens commands + file/symbol search; sidebar **Search** opens the full symbol search page (filter by kind, including keywords).
- **Test Explorer** (Tests rail): tree of workspace → projects → suites → tests/tasks with PASS/FAIL/SKIP/NOT RUN/RUNNING dots; toolbar Run All / Run Current File / Run Failed / Refresh / Expand / Collapse; live filter by suite, test, tag, or file.
- Missing-library run failures (Browser, SeleniumLibrary, …) can prompt Install via snackbar.

---

## Tests

### Widget / unit

```bash
cd frontend
flutter test
flutter analyze
```

Notable suites under `test/`:

| File | Covers |
|------|--------|
| `editor_tabs_context_menu_test.dart` | Editor tab right-click Close/Others/All/Saved/Right + path actions |
| `widget_test.dart` | Welcome, dialogs, managers, toolbar, editor shells |
| `editor_syntax_test.dart` | File-extension → re_highlight / custom Robot theme mapping |
| `virtual_file_tree_test.dart` | Virtualized explorer, context menus, inline rename, silent `.robot` append, shortcuts |
| `side_panel_resize_test.dart` | Side panel drag resize handle + width clamps |
| `explorer_file_icon_test.dart` | Material Icon Theme file/folder glyphs |
| `test_explorer_panel_test.dart` | Test Explorer tree, search, toolbar, expand/status |
| `status_bar_test.dart` | ROBOT / PYTHON labels, project name, hidden version slots |
| `ux_guidance_test.dart` | Guidance dialog + recent-item tooltips |
| `ux_polish_ab_test.dart` | Status bar omits connection chrome; Run/Stop styling, Last: run badge, report hyperlink |
| `workspace_live_events_test.dart` | Workspace event parsing, StatusBar notification slot, Git debounce |
| `execution_stream_status_test.dart` | Cold-start idle vs stale run status |
| `reports_side_panel_test.dart` | Reports side panel uses real runs |
| `git_widget_test.dart` | Source control widgets |
| `problems_panel_test.dart` | Problems list empty state + click |
| `problems_loop_test.dart` | Reveal Problems tab, status-bar ERRORS shortcut, location labels |
| `command_palette_test.dart` | Palette filter, Enter activate, workspace file results |
| `backend_health_retry_test.dart` | Health probe retries; transient failures ignored; offline after consecutive misses |
| `plugin_manager_test.dart` | Plugin manager layout / rows |
| `ux_polish_sprint_test.dart` | Error dialog Show details, env toast copy, collapsed rail, bottom tabs, hidden Settings |
| `ux_polish_pre_m14_test.dart` | Skeleton loaders, EmptyState semantics, explorer selection, status bar tooltips, timeout copy |

### Integration (E2E)

Prefer the repo script so macOS sandbox can reach Python:

```bash
# From repository root
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
