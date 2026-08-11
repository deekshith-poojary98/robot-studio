# Definition of Quality

**Hold every PR against this document before merge.**  
If a change fails a section that it touches, it is not ready — even if the feature “works on my machine.”

Companion to `polish.md` (what we burn down) and [`ARCHITECTURE.md`](../../ARCHITECTURE.md) (system map).

**Judge every change by three questions:**

1. Does it improve the daily workflow of an RF SDET?
2. Does it preserve the single-owner architecture?
3. Would I still merge this one week before public beta?

If any answer is **no**, it belongs after 1.0.

---

## PR Checklist (Definition of Done)

Copy into the PR description (or confirm each line in review). Reviews stay consistent instead of relying on memory.

### User Value

- [ ] Solves a real user problem
- [ ] No unnecessary surface area added

### Reliability

- [ ] No data-loss path introduced
- [ ] No wrong-run scenario introduced
- [ ] Bug fix includes an automated regression test **or** a documented reason why it cannot

### Architecture

- [ ] Uses existing semantic owner
- [ ] No duplicate cache / service
- [ ] No direct parser / libdoc calls from UI

### Verification

- [ ] Unit / integration tests (where applicable)
- [ ] Manual verification (note what was checked)
- [ ] Documentation updated if behavior changed (`polish.md` evidence, README, `ARCHITECTURE.md`)

---

## Reliability

- Never loses user work (dirty buffers, save, auto-save, crash recovery paths).
- Never runs the wrong suite (explicit run target; no silent fallback to “first suite”).
- Never corrupts settings (`SettingsService` only; versioned `settings.json`).
- Never blocks the UI unexpectedly (long work off the UI isolate / async; clear busy states).
- Never invents ghost identity (delete/recreate → new id; move/rename → same id).
- Never resurrects a deleted project/folder via Save.
- Emergency Lane items (crash, corruption, won’t open, wrong suite) outrank polish.
- **Regression rule:** Every bug fix should include either an **automated regression test** or a **documented reason why it cannot**. That single rule pays dividends over time.

---

## Performance

Targets for a **typical** project unless noted:

| Interaction | Target |
|-------------|--------|
| Cold start | &lt; 5 s |
| Find in Files | &lt; 500 ms (medium project) |
| Completion | &lt; 100 ms perceived |
| Signature Help | Feels instant |

Also:

- Large project (1000+ tests) remains responsive (scroll, outline, run discovery).
- No unbounded memory growth after a long editing session.
- Indexing / analysis must not freeze input; progress may be visible.

---

## Usability

- Every dialog has a clear primary action and a way out.
- No duplicate commands (menus, palette, toolbar, Tests page).
- No navigation dead ends (every chrome path lands somewhere useful).
- Keyboard-first workflow for daily editing, run, find, and save.
- Errors are friendly first; details are opt-in (copyable).
- Empty states explain the next step.

---

## Architecture

### Guiding principle

> **Every semantic concept has exactly one owner.**

Consumers are read-only. Everything else in this section flows from that rule.

| Concept | Owner |
|---------|--------|
| Application preferences | `SettingsService` |
| Libraries / libdoc keywords | `LibraryCatalogService` |
| Live document symbols / fold / outline tree | `DocumentAnalysisService` |
| Workspace / project identity & open lifecycle | `WorkspaceService` / project services (durable id in `.robotstudio`) |
| Execution runs + failed-test knowledge | `ExecutionService` / `ExecutionKnowledgeService` |
| Index symbols (workspace search) | IndexStore / IndexService |

### Rules

- No feature bypasses these semantic services to call parser workers or libdoc directly from widgets.
- No duplicate semantic caches (one catalog, one document analysis cache, one settings file).
- No parser calls from Flutter widgets — gateway / backend only.
- Settings only through `SettingsService` (API → `AppSettingsController`); never read `settings.json` from UI code.
- Typed models at boundaries (`KeywordMetadata`, `LibraryMetadata`, `DocumentSymbolTree`, `AppSettings`); dicts only at transport edges.
- **No refactors without user value** in late beta unless required to fix Reliability / Emergency issues.

---

## Release

### Release blockers (after RC — these only)

| Blocker | Meaning |
|---------|---------|
| Crash | Uncaught exception, hard quit, hung UI |
| Data loss | User work / settings / reports destroyed or silently wrong |
| Wrong suite executed | Run targets incorrect file or silent fallback |
| Cannot open project | Open / recent / locate paths broken |
| Identity corruption | Ghost ids, wrong env binding, resurrected paths |
| Severe performance regression | Cold start / search / editing unusable vs prior RC |

Everything else waits for a post-beta patch or 1.0.

### Before calling a build a Release Candidate

- [x] `polish.md` freeze criteria checked — large project + P0; startup/memory/menu smoke still open and **not** a private-beta gate
- [x] P0 Exit met (leftover highlighter / completion sweeps in Deferred)
- [x] Emergency Lane empty
- [ ] Menu smoke: every menu command exercised once
- [x] Docs match shipped behavior — Install / README point at GitHub Releases; testers file GitHub Issues
- [x] Feedback available — GitHub Issues (in-app Send Feedback deferred)

**North-star:** Can an RF SDET spend an entire week in Robot Studio without opening VS Code?
