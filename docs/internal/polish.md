# Epic 4 — Product Polish

**Contract for the rest of beta.**  
Once written, **do not add features** to this board. Only move items between priorities, mark them done, or consciously defer them (see **Deferred**).

---

## Goals

1. Make Robot Studio feel **trustworthy** for an RF SDET who stays in it all day.
2. Clear every **P0** item (or consciously defer with a written reason).
3. Meet **freeze criteria**, then ship a **Release Candidate**, then public beta.
4. Measure progress by **reliability and workflow**, not features shipped.

**North-star question (every change):**

> Does this make Robot Studio feel more reliable to someone who uses it 8 hours a day?

If the answer is no, it does not belong in beta.

**Status (2026-08-12):** P0 exit met. Private beta distribution is [GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases) (zip of `.app` / `RobotStudio.exe` — not an installer). Testers file bugs on GitHub Issues. In-app Send Feedback is deferred. A suite with ~10k test files stayed responsive.

---

## Operating rules

1. **≤ 1 day to implement.** If it takes a week, it is another feature — move to **Deferred** with a target.
2. **No new capabilities** during this epic.
3. Prefer fixing **trust** over polish chrome.
4. Every completed P0 item should immediately make the product feel more trustworthy.
5. Items only **move between priorities**, get **done** (with evidence), or go to **Deferred** — they are not expanded into new feature work.
6. **Emergency Lane** always interrupts everything else.
7. After Release Candidate: **release blockers only** (enumerated below).
8. After public beta freeze: bug fixes, UX polish, performance, crashes only.
9. **No refactors without user value** late in beta (see Out of scope).
10. PRs use the **PR Checklist** in `quality.md` — reviews do not rely on memory.

### How to mark done

When checking an item, leave short **Acceptance Evidence** underneath:

```md
- [x] Stop button spacing / alignment
      Evidence: verified macOS + Windows; toolbar screenshot in PR
```

or:

```md
- [x] …
      Verified: manual checklist / beta user confirmed / automated test `…`
```

After ~100 fixes, evidence is what prevents "we thought we fixed that."

---

## Release stages

```
Feature Complete          ← Epic 2 + Preferences shipped
        ↓
Polish Complete           ← P0 exit + GitHub Issues + quality.md
        ↓
Release Candidate         ← We believe we could ship today
        ↓
Public Beta               ← Only release blockers after RC
```

**Release Candidate** means: we believe we could ship today. After RC, only the **Release blockers** list below is allowed. No "while we're here" polish.

### Release blockers

| Blocker | Meaning |
|---------|---------|
| Crash | Uncaught exception, hard quit, hung UI |
| Data loss | User work / settings / reports destroyed or silently wrong |
| Wrong suite executed | Run targets incorrect file or silent fallback |
| Cannot open project | Open / recent / locate paths broken |
| Identity corruption | Ghost ids, wrong env binding, resurrected paths |
| Severe performance regression | Cold start / search / editing unusable vs prior RC |

Everything else waits.

### User Guide milestones

| Milestone | Status | Meaning |
|-----------|--------|---------|
| **User Guide — Content Validation** | **PASS** | Guide matches shipped UI for someone who already has a build (install → run → Preferences journey verified against product code). |
| **User Guide — Beta Onboarding** | **Ready when a Release exists** | Testers download the zip from GitHub Releases, then follow Install → first project → first run. Linux is not a packaged target. |

Do **not** open another “fix the docs” iteration for content correctness. Next docs gate is a **zero-context test** on a published release: guide + zip → unzip → project → env → run → failure → source → Preferences, with no verbal coaching.

### Beta onboarding blockers (not User Guide backlog)

| Item | Owner | Priority | Status |
|------|-------|----------|--------|
| Replace “Test Explorer” in Execution idle copy with **Tests** | Product/UI | P1 | **Done** (see P1) |
| Private-beta artifact path | Release/Packaging | **Beta blocker** | **GitHub Releases** — zip of `Robot Studio.app` / `RobotStudio.exe`. Publish the first release, then testers use the Install guide. |

Linux is **not** a packaged beta target. No `.dmg` / `.msi` installer for beta.

---

## Emergency Lane

These **interrupt all work** — including active P0 items. Do not queue behind fuzzy package search.

| Class | Examples |
|-------|----------|
| Crash | Uncaught exception, hard quit, hung UI |
| Data corruption | Settings / identity / index / reports wrong or destroyed |
| Project won't open | Open / recent / locate paths broken |
| Wrong suite executed | Run targets incorrect file or silent fallback |

Track open emergencies here (keep empty when healthy):

- _(none)_ — audited 2026-08-05; P0 exit 2026-08-12. Wrong-suite refusal + no-resurrect save already guarded.

---

## P0 — Trust

Almost all burn-down time goes here.

### Package / Reports / Chrome

- [x] Package search supports partial / fuzzy matching
- [x] Remove PASS badge from Reports — result status badge removed from run details; failure counts stay emphasized; Last Run shows “Finished” on success and emphasizes FAIL
- [x] Stop button spacing / alignment — Run / Project / Stop are one segmented bar (`ux_polish_ab_test.dart`)
- [x] Toolbar spacing consistency (Stop + run controls) — same segmented control, equal width/height, zero gap

### Appearance

- [x] Settings → Theme actually applies — the control was inert: the preference persisted but every colour came from `static const` dark tokens (`AppColors`, 593 refs / 72 files), so swapping `ThemeData` repainted nothing. Tokens are now `AppPalette` (a `ThemeExtension`, read via `context.palette`), both brightnesses build from one `buildAppTheme(palette)`, and the theme sits on `MaterialApp` so dialogs/menus/`system` mode follow — `test/app_theme_test.dart` (wiring + const-repaint + WCAG contrast), `editor_syntax_test.dart` (Dark+/Light+), `widget_test.dart` (end-to-end Light with a dark-token leak guard)

### Absolute blockers (also Emergency Lane if open)

- [x] Any known **crash** — none open (Emergency Lane empty 2026-08-05)
- [x] Any **data-loss** bug — save refuses when workspace gone (`test_save_does_not_resurrect_*`); auto-save cancels on missing project / quiet failure
- [x] Any **wrong-suite run** / navigation dead end that blocks daily use — `resolveRunTargetPath` refuses sticky suite while non-`.robot` focused (`test/run_target_test.dart`)

### Editor / Language

- [x] Auto-save edge cases (dirty tabs, rapid edits, save-before-run interaction) — timer cancelled on missing project; quiet auto-save failures (no dialog spam); no write while project missing
- [x] Known syntax highlighting bugs that blocked daily use — keyword name after a whitespace-only line (`editor_trust_fixes_test.dart`). Open-ended highlighter polish is **Deferred**.
- [x] Completion good enough for daily RF authoring. Open-ended completion sweeps are **Deferred**.

### Identity / Finder / lifecycle (from `edgecase.md`)

Highest value first:

- [x] Delete in Finder → recreate same name → open — **new** identity; no ghost envs/reports — `test_recreate_same_path_mints_new_workspace_id` + `test_reopen_purges_missing_run_artifacts`
- [x] Delete open project → Close → New Project same name — fresh open; **No environment**, not `venv · missing` — Close standalone clears session envs; `_applyOpenedWorkspace` clears env list before reload (`shell_paths` / session unload)
- [x] Quit → delete project → relaunch → Recent Projects — clear failure / purged entry (no crash) — `test_recent_ignores_missing_directories` (workspace recent)
- [x] Delete only env folder while open — `· missing`; Run blocked — `test_missing_venv_marked_unavailable`
- [x] Create env A, delete folder, Create env B same name — succeeds; A not stuck active — `test_recreate_same_name_after_folder_delete_activates_new`
- [x] Delete open project → Dismiss → edit & Save — friendly failure; folder must **not** resurrect — `test_save_does_not_resurrect_*` / `test_writes_refuse_to_recreate_deleted_workspace`
- [x] Quit via ⌘Q — sidecar stop via pid file + native terminate hooks (packaged app). Further orphan reports are GitHub issues, not an open P0.
- [x] Packaged app create env — succeeds even if backend cwd was deleted — `test_stable_subprocess_cwd_skips_missing_preferred`

### P0 Exit

**MET 2026-08-12.**

1. No P0 checkbox remains unchecked (leftover highlighter / completion sweeps are in **Deferred**).
2. No Emergency Lane items open.
3. Deferred former-P0 items have a written rationale in **Deferred**.

---

## P1 — Workflow

- [x] Replace “Test Explorer” in Execution idle subtitle with **Tests** (matches activity-bar label + user guide)
      Evidence: `execution_page.dart` + `execution_page_test.dart`
- [ ] Outline quality improvements
- [ ] Explorer polish (selection, New File root, keyboard)
- [ ] Report readability / nicer summaries / last-run actions
- [ ] Package install UX (names, loading polish)
- [ ] Interpreter label cleanup
- [ ] Breadcrumbs / Outline polish leftovers from Document Intelligence
- [ ] Remaining `edgecase.md` items not in P0 (files, git chrome, welcome)

### P1 Exit

P1 is complete when:

1. Remaining open items are **cosmetic only** (or Deferred).
2. No workflow issue requires opening VS Code to finish a normal RF day.
3. No duplicated commands / run controls remain in the UI.

---

## P2 — Performance

- [x] Large project indexing (1000+ tests remains responsive) — manual check 2026-08-12 on a suite with ~10k test files; stayed usable
- [ ] Startup profiling (target: cold start &lt; 5 s on a typical project) — not separately timed; not a private-beta gate
- [ ] Search responsiveness (Find in Files)
- [ ] Package cache
- [ ] Memory leaks / growth after long editing session
- [ ] Animation smoothness

### P2 Exit

P2 is complete when:

1. Freeze performance criteria below are met with noted evidence.
2. Remaining items are measurement follow-ups, not user-visible jank.

---

## P3 — Paper cuts

Same rule: **≤ 1 day**. Collect small annoyances here; burn after P0/P1 unless trivial and adjacent to an open file.

_(P0 is clear. Collect paper cuts here; they do not block private beta.)_

### P3 Exit

P3 never blocks RC. Paper cuts may continue under freeze rules; they do not reopen the feature surface.

---

## Deferred

**Deferred** means: we will do it later (has a target release).

Items removed from the active board without lying about them. Prefer this over deleting.

| Item | Reason | Target |
|------|--------|--------|
| Unified Search (`⌘⇧P` IDE OS) | Large feature | 1.0 |
| Multi-cursor | &gt;1 day / editor platform | 1.1 |
| Workspace-specific settings | Preferences non-goal for beta | 1.1 |
| Keybinding editor / theme designer | Preferences non-goal | later |
| Plugin configuration UI | Preferences non-goal | later |
| Open-ended syntax highlighting sweep | Known daily-use bugs fixed; rest as GitHub issues | post-beta |
| Open-ended completion edge-case sweep | Daily authoring works; rest as GitHub issues | post-beta |
| In-app Send Feedback (Help menu) | Testers file bugs on GitHub Issues for private beta | 1.0 |

_(Add rows as P0/P1 items are consciously deferred.)_

---

## Won't Fix (Beta)

**Won't Fix (Beta)** means: we intentionally decided this is **not for beta** — do not reopen the same discussion unless product goals change.

| Item | Reason |
|------|--------|
| AI | Explicit non-goal for beta |
| Replay | Explicit non-goal for beta |
| Debugger | Explicit non-goal for beta |
| Impact analysis | Explicit non-goal for beta |
| Flaky test detection | Explicit non-goal for beta |
| Git graphs / fancy dashboards | Explicit non-goal for beta |
| Telemetry / analytics | Feedback stays manual |
| Refactors without user value | Late-beta regression magnet |

If someone proposes one of these during polish, point here and move on.

---

## Planned after P0 (not a feature epic)

In-app **Send Feedback** (Help → Report Bug / Request Feature / Copy Diagnostics / Open Logs) is **Deferred** to 1.0. Private beta feedback is [GitHub Issues](https://github.com/deekshith-poojary98/robot-studio/issues).

---

## Freeze criteria

Declare **Polish Complete → Release Candidate** only when **all** of the following are true:

- [x] No known crashes — Emergency Lane empty
- [x] No data-loss bugs — save refuses when workspace gone; auto-save cancels on missing project
- [x] No navigation dead ends — run target refuses silent fallback
- [x] No duplicated UI (commands / run controls / chrome) — Tests page is monitoring-only; Run lives on the toolbar
- [ ] Startup &lt; 5 seconds on a typical project — not separately timed
- [x] Large project (1000+ tests) remains responsive — ~10k test files, 2026-08-12
- [ ] No memory growth after a long editing session (spot-check / profiler note)
- [ ] Every command reachable from menus is exercised once (smoke pass)
- [ ] Every beta / `edgecase.md` issue is either **fixed**, listed in **Deferred**, or listed in **Won't Fix (Beta)** — P0 subset done; leftover file/git/welcome cases stay on P1
- [x] Documentation matches the shipped product — Install points at GitHub Releases
- [x] `quality.md` exists and is used as the PR standard (checklist answered on PRs)
- [x] Testers can send feedback — GitHub Issues (in-app Help menu deferred)
- [x] P0 Exit conditions met — 2026-08-12

Then: **Release Candidate** — only the Release blockers table.  
Then: **Public Beta** under the same discipline.

---

## Out of scope until 1.0+

Do **not** pull these onto the active board. Prefer **Deferred** (later) or **Won't Fix (Beta)** (intentionally not beta) over silent drops.

| Area | Bucket |
|------|--------|
| Unified Search (`⌘⇧P` OS) | Deferred → 1.0 |
| AI / Replay / Debugger / Impact / Flaky detection | Won't Fix (Beta) |
| Git graphs / fancy dashboards | Won't Fix (Beta) |
| Plugin configuration / workspace settings / keybinding editor / theme designer | Deferred |
| Telemetry / analytics | Won't Fix (Beta) |
| **Refactors without user value** | Won't Fix (Beta) unless required to fix a P0/Emergency |

Anything that fails the **≤ 1 day** rule belongs in **Deferred** or a future epic — not in P0–P3 expansion.

Resist slipping Unified Search (or any shiny feature) in when P0 shrinks. That discipline is what ships.

---

## Related docs

| Doc | Role |
|-----|------|
| `edgecase.md` | Manual trust / lifecycle checklist (feeds P0 / P1) |
| `quality.md` | Definition of Quality — hold every PR against it |
| [`ARCHITECTURE.md`](../../ARCHITECTURE.md) | Broader system map; semantic owners summarized in `quality.md` |

---

## Burn-down order

1. ✅ Write / refine this file (`polish.md`)
2. ✅ Write `quality.md` (PR standard)
3. ✅ Burn down **Emergency Lane** whenever non-empty, then every **P0** item
4. ✅ Private beta feedback = GitHub Issues (in-app Send Feedback deferred)
5. Publish the first GitHub Release zip → testers follow the Install guide
6. Remaining freeze boxes (startup timing, memory, menu smoke) do not block private beta
7. **Public Beta** — release blockers only

After that, think like a product owner preparing a release — not an engineer adding surface area.
