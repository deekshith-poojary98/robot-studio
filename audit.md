# Robot Studio — Pre-Release Engineering Audit

Analysis-only review of the codebase at milestones M10/M11 (intelligent editor + plugin framework). No code was modified.

---

# Overall Architecture Score

**6.5 / 10**

The project has a **clear intended architecture** (ports/adapters, EventBus, PluginHost, TransportGateway, WorkspaceContext) and a **reasonable module layout**. For an alpha desktop IDE, the layering is better than average. Before a public release, several **documented principles are not fully realized**, and a few **production blockers** (security, scalability, plugin swap-ability, dual parsing) would surface quickly with real users, large workspaces, or any exposure beyond localhost.

---

# Biggest Strengths

1. **Documented clean architecture** — `ARCHITECTURE.md` defines Event Bus, Plugin Host, Index-backed language intelligence, and transport abstraction with explicit rules. The team knows where they want to go.

2. **Consistent backend layering** — Domain interfaces (`Runner`, `LanguageService`, `Installer`, etc.) with application facades (`LanguageFacade`, `PluginService`) and a thin `RestGateway` adapter. No obvious import cycles at the module level.

3. **TransportGateway abstraction (frontend)** — Flutter depends on an interface, not HTTP directly. `RestTransportGateway` is injectable; tests use a fake gateway. This is the right long-term shape for REST → gRPC migration.

4. **Workspace-scoped file access** — `FileService._resolve_under_workspace()` uses `resolve()` + `relative_to(root)` for path containment. Solid baseline for editor file I/O.

5. **Event-driven decoupling (partial)** — Index rebuild on workspace/project events, report indexing on execution finish, language cache invalidation on `IndexUpdated` — matches the architecture doc’s intent.

6. **Incremental indexing model** — `index_files` mtime tracking, `SqliteIndexStore` with indexes on name/kind/file/project/workspace, incremental file indexing in `IndexService`.

7. **Robot parsing bridge (M10)** — Moving language intelligence toward `robot.api.parsing` via workspace venv subprocess is the correct direction for RF compatibility.

8. **Test discipline for APIs** — ~78 backend tests across 18 files, happy-path API coverage for major modules, architecture smoke tests for health/event bus.

9. **Presentation/widget separation** — Most UI is stateless pages receiving props (`PackageManagerPage`, `EnvironmentManagerPage`, `EditorPage`). Dialogs are mostly extracted.

10. **Plugin lifecycle foundation (M11)** — Manifest validation, discovery paths, lifecycle hooks, events, Plugin Manager UI — a real extension framework skeleton exists.

---

# Critical Issues (must fix before release)

| # | Issue | Location | Impact |
|---|--------|----------|--------|
| 1 | **Execution can run arbitrary absolute paths** | `ExecutionService._resolve_suite()` — absolute paths are not constrained to project root | Run any `.robot` file on disk if path is known |
| 2 | **Unsandboxed plugin loading** | `plugin_runtime.py` — `exec_module` with full Python privileges from `~/.robotstudio/plugins` and `{workspace}/Plugins` | Malicious plugin = full machine access |
| 3 | **No authentication; permissive CORS** | `main.py`: `allow_origins=["*"]` + `allow_credentials=True` | Invalid CORS combo; unsafe if API is ever exposed |
| 4 | **Dual parsing pipelines diverge** | Indexing: regex `RobotIndexer`; Language: `robot_parsing_worker` / `get_model` | Inconsistent symbols, diagnostics, completion, outline |
| 5 | **Plugins cannot replace core capabilities** | `PluginManager._register_capabilities()` only registers UI extensions; Container hardcodes all factories | PluginHost is mostly metadata; architecture promise unfulfilled |
| 6 | **`app_shell.dart` god widget (~2,809 lines)** | ~70 state fields, ~100 `setState`, all domains in one class | Unmaintainable; every feature increases regression risk |
| 7 | **Polling file watcher at 1.5s** | `PollingFileWatcher` — full `rglob` snapshot every poll | Unusable at thousands of files |
| 8 | **Editor controller recreated on diagnostics change** | `robot_code_editor.dart` lines 115–126 | Lost undo, flicker, jank on every LSP refresh |

---

# High Priority Issues

### Architecture violations
- **`LanguageFacade` leaks infrastructure** — uses `getattr(self.language, "store")` instead of a port.
- **`ReportService` bypasses PluginHost** — not routed through `ReportProvider` for indexing/open behavior.
- **`ExecutionService` / `ReportService` use `isinstance` on concrete types** — breaks Liskov and plugin substitution.
- **WebSocket bypasses gateway** — `execution/stream` uses global `container` directly.
- **Application layer imports infrastructure** — `PluginService` → `PluginManager`; `IndexService` → concrete repositories.
- **Single global `WorkspaceContext`** — one workspace/project/environment per process; no multi-session model.

### SOLID
- **SRP violations**: `EnvironmentService` (~499 lines), `RobotLanguageService` (~486), `SqliteIndexStore` (~487), `ExecutionService` (~428), `AppShell` (~2,809).
- **OCP**: Adding features requires editing Container + AppShell, not extending via plugins.
- **DIP**: Application services depend on `Sqlite*` repositories and concrete infra types.

### API
- Language GET endpoints pass **`content` in query strings** — URL limits, logging exposure.
- **No pagination** on projects, environments, packages, plugins, execution history (hardcoded limit 50).
- **No request size limits** on file write.
- **`PluginService.refresh()`** exists but no REST route exposes workspace plugin re-discovery after open.

### Database
- **No unified migration system** — `schema_version` table written but never read; only execution repo has `ALTER TABLE` try/except.
- **New connection per repository call** — no pool, no WAL.
- **`LIKE '%query%'` search** — won’t scale; no FTS.

### Frontend
- **Root `setState` on every keystroke and cursor move** — full tree rebuild.
- **`_refreshWorkspaceProblems`** — sequential diagnostics per open tab after each language refresh.
- **100ms timer during execution** — full shell rebuild for elapsed label.
- **Boolean navigation flags** (`_showEditorPage`, `_showPackageManager`, etc.) — error-prone state machine.

### Security (medium-high)
- **Symlink escape** in workspace file paths ( `resolve()` follows symlinks).
- **`SubprocessRunner._runs` never pruned** — memory growth on long-lived backend.
- **Unbounded Robot parsing subprocesses** — no pool/rate limit per diagnostics/completion/format call.

---

# Medium Priority Issues

| Area | Issue |
|------|--------|
| **Duplication** | Symbol ID hashing in 3 places; skip patterns for venv/`__pycache__` repeated; import dialog pairs nearly identical; `ApiClient` is pure delegate (~359 lines, unused in lib) |
| **Indexing** | Full workspace rebuild on every project open/create/import; sequential rebuild loop; `FileIndexed` per file during rebuild (event flood) |
| **Language** | `_append_semantic_diagnostics` N+1 DB queries; loads 500+200+200 symbols every diagnostics call; regex indexer stores empty `symbol_id` on references |
| **Python indexer** | `python_indexer.py` — `@keyword` detection uses `or True`, indexing all public methods |
| **Plugin UX** | Built-ins cannot be disabled; `report-service` plugin has empty capabilities; NoOp fallback for invalid plugins |
| **Reports** | `ReportService` opens HTML via OS shell (`open`/`xdg-open`/`explorer`) — paths from DB |
| **Tests** | No security tests; no WebSocket tests; no `FileService` unit tests; no parsing bridge tests; fake gateway embedded in 2,221-line `widget_test.dart` |
| **Theme** | Dark-only tokens; `SF Pro Text` / `Menlo` not bundled; mixed toolbar button styles |
| **Editor** | Format selection likely single-line only; Open/Workspace Symbol dialogs return first match only; hover via toolbar not pointer |
| **EventBus** | Handler exceptions swallowed; no backpressure; dual pub/sub for execution (EventBus + internal queue) |

---

# Low Priority Issues

- ARCHITECTURE.md mentions gRPC/WebSocket event stream to frontend — not implemented (execution WS only).
- `REGISTERED_MODULES` in health is static; doesn’t reflect loaded plugins/capabilities.
- `document_symbols` in parsing worker unused; outline always from index store.
- Bottom panel Problems/Output/Terminal still partially placeholder for non-problems tabs.
- No golden/accessibility tests.
- No light/high-contrast theme path.
- Plugin error dialog exists but many failures only hit logs.
- `BUILTIN_PLUGIN_SPECS` duplicates capability IDs already in `register_builtin_capabilities`.

---

# Technical Debt Summary

| Category | Debt |
|----------|------|
| **Architecture drift** | Doc says “plugins replace builtins”; code hardcodes Container + UI-only plugin registration |
| **Parsing debt** | M10 added parsing bridge but M8 regex indexer still authoritative for index/search/outline |
| **Frontend monolith** | AppShell absorbs all new milestones (M9 editor, M10 LSP, M11 plugins) |
| **Schema debt** | Fragmented DDL across 6+ initializers; no migration runner |
| **Test debt** | Wide API happy paths; narrow unit/integration/security coverage |
| **Dead code / stubs** | `ApiClient` unused; parsing worker `document_symbols` unused; AI provider capability declared but unimplemented |

---

# Performance Risks

1. **Polling watcher** — O(files × 0.67 Hz) forever.
2. **SQLite** — per-call connections; fuzzy re-sort in Python after SQL.
3. **Language subprocess storm** — debounced 350ms × 3 parallel calls + N tab diagnostics.
4. **Full AppShell rebuild** — typing, cursor, execution timer, stream lines.
5. **Controller dispose/recreate** — diagnostics update path in editor.
6. **Index rebuild** — synchronous sequential; no parallelism.
7. **Large file editor** — no virtualized/document size limits; full content in memory and HTTP bodies.
8. **Package/environment lists** — full load, client-side filter only.

---

# Scalability Risks

| Scenario | Risk |
|----------|------|
| **5k+ Robot files** | Polling watcher CPU; rebuild time; SQLite search latency |
| **Hundreds of projects** | No pagination; full list API responses |
| **Many open editor tabs** | Workspace problems = O(tabs) diagnostics round-trips |
| **Many plugins** | In-process load; no isolation; single provider per core capability |
| **Long executions** | Unbounded `_executionLines` in Flutter state; unbounded `_runs` in runner |
| **Large reports/output** | Full XML/HTML paths stored; no streaming artifact API to frontend |
| **Many environments** | Full list load; no lazy activation cache |

---

# Security Risks

| Risk | Severity | Notes |
|------|----------|-------|
| Arbitrary suite execution (absolute path) | **Critical** | Outside project boundary |
| Unsandboxed plugins | **Critical** | Full Python + PluginContext services |
| No API auth | **High** | OK for localhost-only if enforced |
| CORS misconfiguration | **High** | `*` + credentials |
| Path traversal via symlinks | **Medium** | FileService |
| PluginContext exposes execution/env/event publish | **High** | By design for IDE plugins; needs trust model |
| pip install with user package names | **Low–Medium** | Standard supply-chain risk |
| Language content in GET query logs | **Low** | Proxies/logging |

---

# Maintainability Risks

**Files becoming too large (pain by M20):**
- `app_shell.dart` (2,809) — primary bottleneck
- `rest_transport_gateway.dart` (809)
- `welcome_screen.dart` (735)
- `widget_test.dart` (2,221)
- `environment_service.py` (499)
- `robot_language_service.py` (486)
- `sqlite_store.py` (487)
- `gateway.py` (436)

**Services with too many responsibilities:**
- `AppShell` — entire application
- `EnvironmentService` — CRUD + import + clone + activate + interpreter discovery
- `RobotLanguageService` — completion, diagnostics, format, signature, semantic analysis, parsing bridge
- `ExecutionService` — run lifecycle + monitor + WebSocket broadcast + suite resolution
- `Container.initialize()` — all wiring

**Missing abstractions:**
- Domain-scoped gateways (WorkspaceGateway, LanguageGateway, ExecutionGateway)
- Unified `ConfirmDialog` / error presentation
- Editor state controller (buffer, cursor, LSP debounce outside shell)
- Migration runner / schema registry
- Plugin capability provider registry (multi-provider, priority)
- Frontend event stream abstraction (matches ARCHITECTURE.md)
- Request cancellation / in-flight deduplication

---

# Suggested Refactors

Ranked by ROI. Scores: Impact (1–5), Difficulty (1–5, higher = harder), Risk (1–5, higher = riskier), Benefit (summary).

| Rank | Refactor | Impact | Difficulty | Risk | Expected benefit |
|------|----------|--------|------------|------|------------------|
| 1 | **Constrain execution paths to project root** | 5 | 2 | 1 | Closes critical security hole |
| 2 | **Split AppShell into domain controllers** | 5 | 4 | 3 | Unblocks all future UI work |
| 3 | **Unify indexing on `robot.api.parsing`** | 5 | 4 | 3 | Single source of truth; fixes symbol/diagnostic drift |
| 4 | **Replace polling watcher with native FS events + debounce** | 5 | 3 | 2 | Scales to large workspaces |
| 5 | **Stop recreating editor controller on diagnostics** | 4 | 2 | 1 | Fixes jank and undo loss |
| 6 | **Scope LSP refresh to active tab; cancel in-flight** | 4 | 3 | 2 | Cuts API/subprocess load 10×+ |
| 7 | **Plugin sandbox / trust tiers** | 5 | 5 | 4 | Required for third-party plugins |
| 8 | **Wire core capabilities through PluginHost for real swap** | 4 | 4 | 3 | Fulfills architecture promise |
| 9 | **SQLite migration system + WAL + connection pool** | 4 | 3 | 2 | Safer upgrades; better concurrency |
| 10 | **Extract WebSocket into TransportGateway** | 3 | 2 | 1 | Consistent transport; testable streaming |
| 11 | **Pagination on list endpoints** | 3 | 2 | 1 | Scales projects/packages/history |
| 12 | **Break up EnvironmentService + RobotLanguageService** | 3 | 3 | 2 | Easier testing and changes |
| 13 | **Remove ApiClient or make it the sole entry point** | 2 | 1 | 1 | Less duplication |
| 14 | **Shared test fakes + AppShell integration tests** | 3 | 2 | 1 | Prevents gateway/shell drift |
| 15 | **Explicit AppView state machine (replace booleans)** | 3 | 3 | 2 | Fewer navigation bugs |

---

# TOP 20 Improvements (Highest Long-Term ROI)

1. **Constrain execution suite resolution to project/workspace boundary** — security foundation.
2. **Decompose `app_shell.dart` into Editor/Workspace/Execution/Plugin controllers** — maintainability unlock.
3. **Migrate `RobotIndexer` to parsing bridge (or formally deprecate regex path)** — consistency across IDE features.
4. **Replace `PollingFileWatcher` with debounced native watching** — scalability for real repos.
5. **Fix editor diagnostic updates without controller recreation** — daily UX quality.
6. **Debounced LSP: active file only + request cancellation** — performance under typing.
7. **Define plugin trust model (signed/trusted/workspace-only) + restrict PluginContext** — safe extensibility.
8. **Implement true PluginHost capability replacement for Runner/Installer/Language/Report** — architecture integrity.
9. **Unified SQLite migrations with versioned schema** — safe releases and upgrades.
10. **Enable WAL + connection pooling for SQLite** — concurrent API + indexing.
11. **Paginate list APIs (projects, envs, packages, plugins, history)** — scale metadata.
12. **Route WebSocket execution stream through gateway with reconnect policy** — transport consistency.
13. **Add FTS or prefix search for symbol index** — fast search at scale.
14. **Parallelize index rebuild (per-project workers)** — faster workspace open.
15. **Extract shared dialog/confirm/error components** — reduce AppShell and test surface.
16. **Remove `isinstance` checks; depend on port interfaces only** — plugin substitution.
17. **Security test suite (paths, execution, plugins, file write limits)** — release gate.
18. **Frontend integration tests for editor save/dirty/LSP/plugin flows** — regression safety.
19. **Rate-limit / pool Robot parsing subprocesses** — protect backend under load.
20. **Document and enforce localhost-only binding + fix CORS** — defense in depth if exposure changes.

---

## Architecture vs. Reality Gap (Summary Diagram)

```
ARCHITECTURE.md promises          Current reality
─────────────────────────         ───────────────
Plugin replaces Runner      →     Container constructs SubprocessRunner directly
Index-backed language       →     Dual parsers (regex index + RF subprocess)
Event stream to UI          →     Only execution WebSocket; not in gateway
Transport abstraction     →     REST good; WS ad hoc
Plugin-ready core           →     Built-ins registered; externals UI-only
Clean AppShell              →     2,809-line monolith
```

---

## Testing Snapshot

| Layer | Approx. count | Gap |
|-------|---------------|-----|
| Backend pytest | ~78 tests / 18 files | Security, watcher, parsing bridge, WebSocket, FileService unit |
| Frontend flutter test | ~37 tests / 3 files | AppShell editor/LSP, RestTransportGateway, re_editor |
| Integration / E2E | None | Full open workspace → edit → run → report flow |
| Architecture enforcement | 5 smoke tests | No layer-boundary lint |

---

## Verdict for First Public Release

Robot Studio is a **credible alpha IDE** with thoughtful architecture documentation and a **working vertical slice** (workspace → env → packages → index → edit → run → reports → plugins UI). It is **not yet production-hardened** for untrusted plugins, large workspaces, or any network exposure.

**Minimum release bar:** fix execution path sandboxing, plugin trust model, dual-parser inconsistency, AppShell decomposition (at least editor/LSP state extraction), and replace polling indexer. **Without those**, the highest-risk failures will be security incidents, UI jank at scale, and symbol/diagnostic mistrust — all fatal for an IDE’s reputation.

---

*This audit is analysis-only. No code was modified. Switch to Agent mode if you want prioritized fixes implemented.*