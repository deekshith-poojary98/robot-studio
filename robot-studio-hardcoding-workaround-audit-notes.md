# Robot Studio — Hardcoding & Workaround Audit Notes

**Purpose:** Keep a record of the hardcoding/workaround audit performed before the private beta release.

**Source:** Cursor Hardcoding & Workaround Audit  
**Last updated:** 2026-09-05 — audit leftovers landed (P2-5: Git extracted, no large split).

---

## Overall Verdict

**Assessment:** NEEDS ATTENTION  
**Private Beta:** ✅ **READY**

The audit found **0 P0**, **5 P1**, **7 P2**, and **4 P3** findings.

The important conclusion is that the codebase does **not** appear to be full of random hardcoded hacks. The main concentration of technical debt is in the **language/editor intelligence stack**, where recent bug fixes have introduced special cases around tokenization, symbol lookup, ranking, and hover behavior.

The execution, settings, sidecar, Windows process, SSL, and large-run handling areas were generally assessed as legitimate product constraints rather than obvious workaround code.

---

# Findings Summary

| Priority | Count | Beta Action |
|---|---:|---|
| P0 | 0 | None |
| P1 | 5 | **P1-1–P1-5 done.** |
| P2 | 7 | **P2-1–P2-7 done.** |
| P3 | 4 | **P3-1 through P3-4 done.** |

---

# Pre-Beta Fixes

## 1. Wildcard Tag Detection — ✅ DONE

**Finding:** P1-4  
**Status:** Done (2026-09-05)

### Problem

Frontend and backend use different logic for detecting wildcard/boolean tag expressions.

Backend effectively checks tokens such as:

```text
"a OR b"
```

Frontend used:

```text
upper.contains("OR")
```

This means tags such as:

```text
important
report
work
```

can incorrectly be interpreted by the frontend as containing a wildcard `OR` expression.

### Action taken

Frontend `LargeRunGuard.isWildcardTag` now matches backend `_assert_large_run_allowed`:

```text
* / ?
" OR " / " AND " / " NOT "   (space-delimited, case-insensitive)
```

Tags such as `important`, `report`, and `work` are no longer treated as boolean expressions.

### Priority

**P1 — fixed before beta.**

---

## 2. `countTests` Failure Must Not Become `0` — ✅ DONE

**Finding:** P2-3  
**Status:** Done (2026-09-05)

### Problem

The previous behavior effectively did:

```text
countTests()
    ↓
error
    ↓
count = 0
    ↓
assume run is small
```

This is unsafe because failure to determine the test count does not mean there are zero tests.

The backend 409 protection still provides a safety net, but the client-side pre-confirmation can be skipped.

### Desired behavior

If test count is unknown:

```text
count unavailable
    ↓
unknown
    ↓
do not assume safe
```

### Action taken

Failed `countTests` is stored as `null`, not `0`. Unknown count does **not** pre-confirm a small run; the client sends `confirm: false` and the backend **409** path still enforces the threshold. Wildcard tags still pre-confirm.

Also: added the missing `package:flutter/scheduler.dart` import so `AppShell`’s existing `SchedulerBinding` notify guard compiles (needed for `widget_test.dart`).

### Priority

**P2 — fixed before beta.**

---

# Deferred Engineering Work

These findings are real, but they should **NOT block the private beta**.

## P1-1 — Variable Identity — ✅ DONE

Robot variables use `${KNOWN_COMMENT_ID}` while Python `Variables` modules expose `KNOWN_COMMENT_ID`. YAML already stored both forms; Python only stored the bare name, so hover had to alias + rewrite.

### Action taken

`PythonLibraryIndexer` now stores the canonical RF name (`${NAME}`) plus the bare name for Python-editor search — same identity as YAML. Hover/definition can hit `${KNOWN_COMMENT_ID}` in the index. Bare-name lookup and display rewrite stay only as fallbacks for older index rows and cold (unindexed) Variables files.

**Status:** Done (2026-09-05).

---

# P1-2 — Multiple Robot Cell Tokenizers — ✅ DONE

Backend hover, diagnostics, signature help, completion, rename, and quick-fixes each split RF cells with slightly different regexes. `_robot_cells_at` only treated two spaces / tabs as separators (`[ ]{2,}`), while everyone else used `[ \t]{2,}`. Diagnostics also used `.split("    ")` for import paths, so tab-separated `Variables` / `Resource` / `Library` lines could keep extra cells.

### Action taken

One tokenizer in `robot_parsing_worker.py` (`split_robot_cells`, `robot_cell_spans`, `first_robot_cell`) is now the backend source of truth. Flutter editor widgets still use a lightweight copy for optimistic caret UI.

**Status:** Done (2026-09-05).

---

# P1-3 — Context-Aware Definition Ranking — ✅ DONE

Default definition order ranked keywords/resources above tags, so `Force Tags    comments` could resolve to `comments.resource`. The previous fix forced `kind = TAG` in SQL.

### Action taken

`find_definitions` takes `prefer_kinds` from caret context (`_caret_definition_kind`). A tag cell ranks tags first without replacing the caller's kind filter. Hover still returns only tags on a tag cell so a missing tag does not jump to a same-named resource.

**Status:** Done (2026-09-05).

---

# P1-5 — Insights Attribution Heuristics — ✅ DONE

Project/Tag/Selected runs used `sole_robot` (credit the only `.robot` in composition) and a one-XML-per-snapshot budget. That skipped `file_outcomes.json` on single-file projects and left later historical runs without per-file fan-out.

### Action taken

Multi-file labels always read `file_outcomes.json` (built from `output.xml` on a cache miss). The one-XML budget is gone. A one-file composition is used only when that sidecar/XML is missing. The empty-composition fold into a single discovered suite stays for the same gap.

**Status:** Done (2026-09-05).

---

# P2 Findings

## P2-1 — Create Dictionary Allowlist — ✅ DONE

Validation used a keyword-name allowlist for `create dictionary` because libdoc shows `*items` only.

### Action taken

Removed `_FREE_NAMED_DESPITE_LIBDOC`. Robot only treats `name=value` as a named argument when the spec has named slots or `**kwargs`. Varargs-only signatures (Create Dictionary, Create List, Set Variable) keep those cells as positional `*items`. Keywords with named parameters still report `unknown_argument` for typos such as `nme=INFO`.

**Status:** Done (2026-09-05).

---

## P2-2 — Stacked `setState` / Notify Guards — ✅ DONE

Three layers used to protect against `setState` during editor mount. The AppShell `SchedulerPhase.persistentCallbacks` guard deferred **every** controller notify during a frame, which can hide real lifecycle bugs.

### Action taken

Removed the shell-level phase deferral. The precise guards stay:

- `RobotCodeEditor` skips the re_editor `delegate=` / mount echo (`_lastEmittedContent`)
- `EditorShellController.onContentChanged` is a no-op when text is unchanged

**Status:** Done (2026-09-05).

---

## P2-3 — `countTests` Failure — ✅ DONE

See **Pre-Beta Fix #2** above. Unknown count is `null`; backend 409 remains the safety net.

---

## P2-4 — Dual Filesystem Debouncing — ✅ DONE

Watcher debounce (0.35s) and analysis rebind debounce (0.75s) ran independently, so the symbol index could update while bindings stayed stale for another 0.75s.

### Action taken

Watcher / filesystem-event indexing now uses `analysis_rebind=False` and finalizes analysis once after the flush (`sleep(0)` so sibling events in the same batch share one rebind). The 0.75s rebind timer remains only for direct `index_file(rebind=True)` bursts (e.g. import-chain tests).

```text
Filesystem watcher
      ↓
0.35s debounce
      ↓
Index (rebind=False)
      ↓
finalize_analysis
```

**Status:** Done (2026-09-05).

---

## P2-5 — `AppShell` Size / Responsibility — ✅ DONE (incremental)

The audit asked not to do a large pre-beta split. Git status, history, diff, commit, branch, and remote operations moved into `GitShellController`. AppShell still owns source-control navigation and identity/remote dialogs (they need `BuildContext`). Further extractions (environments, autosave, test tree) stay follow-up work.

**Status:** Done (2026-09-05) — incremental, not a full shell rewrite.

---

## P2-6 — Hover Detail Denylist — ✅ DONE

Hover `detail` mixed keyword signatures with section labels such as `test case|tags:smoke,critical`. The frontend sniffed those strings to decide whether to show argument chips.

### Action taken

Hover payloads now include `detail_kind`:

```text
signature    keyword [Arguments] / libdoc params
annotation   section, tag, library, or kind label
```

The editor uses that field first. The old section-label denylist remains only as a fallback for payloads that omit `detail_kind`.

**Status:** Done (2026-09-05).

---

## P2-7 — Imported Variable Fallback — ✅ DONE

Hover could inspect imported Python/YAML `Variables` files when the index was cold, but imported `.resource` variable declarations were missing until a full workspace rebuild walked those files independently.

Incremental `index_file(suite)` did not follow `Resource` / `Variables` imports, so `${SHARED}` from `common.resource` was absent from the symbol store.

### Action taken

`FilesystemIndexer.index_file` now follows on-disk `Resource` and `Variables` targets (workspace skip-dirs excluded, cycles via a seen set). Hover still uses the existing index + Python/YAML fallback — no new AST-on-hover special case.

**Status:** Done (2026-09-05).

---

# P3 Findings

## P3-1 — Explorer Modifier Keys — ✅ DONE

Explorer click-to-toggle previously accepted Cmd **or** Ctrl on every platform so widget tests (default Android) could use Meta.

That made Control+click toggle multi-select on macOS and Command+click toggle it on Windows/Linux.

### Action taken

`VirtualFileTree` now uses the same primary modifier as its keyboard shortcuts:

```text
macOS → Meta
Windows/Linux → Control
```

Widget tests set `debugDefaultTargetPlatformOverride` and send the matching key.

**Status:** Done (2026-09-05).

---

## P3-2 — `Create Dictionary` Popular Parameter Hint — ✅ DONE

A ranking hint contained:

```text
create dictionary → &{kwargs}
```

which never matched libdoc's `*items` parameter name (`items`), so the boost was dead.

### Action taken

`_POPULAR_PARAM_NAMES` now uses `items`, matching libdoc / `ParameterMetadata.name`.

P2-1 now models this as varargs-only (no keyword-name allowlist).

**Status:** Done (2026-09-05).

---

## P3-3 — Outline Refresh Error Swallowing — ✅ DONE

Best-effort `catch (_)` around `analyzeDocument` hid analysis failures while completions and diagnostics still updated.

### Action taken

- Incremental refresh still keeps the last good outline (do not flash empty on a transient analysis error).
- Initial `loadOutline` still clears the pane so a failed open does not hang on a spinner.
- Both paths now `AppLogger.warn` the failure (`Outline refresh failed` / `Outline load failed`).

**Status:** Done (2026-09-05).

---

## P3-4 — Duplicate GET/POST Hover Contracts — ✅ DONE

GET and POST both existed for hover / definition / references, with copy-pasted handlers. GET also accepted a `content` query that could not carry a real buffer.

### Action taken

- GET and POST share one helper each (`_hover_result`, `_definition_result`, `_references_result`).
- GET is name/index-only (no `content` query).
- POST is the canonical first-party contract (index and/or live buffer).
- Flutter `RestTransportGateway` always POSTs; GET remains for tests / integration / external callers.

**Status:** Done (2026-09-05).

---

# Legitimate Hardcoding / Constants

The audit explicitly checked hardcoded values that are **not** considered suspicious.

Examples:

### Robot Framework artifacts

```text
output.xml
log.html
.robotstudio/reports/
```

These are product-defined artifact names.

### Large Run Threshold

```text
100
```

is legitimate as the default because it is now wired through the Settings model.

### Platform-specific behavior

```text
Platform.isMacOS
```

is legitimate where behavior genuinely differs by platform.

### Windows PyInstaller constraints

Avoiding `ProcessPoolExecutor` in frozen Windows builds is a packaging/runtime constraint.

### SSL probe

Checking SSL before venv pip operations is legitimate because pip requires HTTPS connectivity.

### Health hysteresis

```text
offlineFailureThreshold = 3
```

is intentional hysteresis, not an arbitrary timing workaround.

### Symbol IDs

```text
sha1(...)[:24]
```

is acceptable because this is used for symbol identity rather than security.

### UI timing

Examples such as hover delay and editor debounce are legitimate UX behavior.

---

# Timing / Race Condition Audit

No major production timing hack was found.

### Legitimate timing

- File watcher debounce: 0.35s
- Editor language debounce
- Cursor UI debounce
- Autosave: 2s
- Health polling
- Explorer/Git/Tests live debounce
- Hover delay
- Report skeleton timer
- `asyncio.sleep(0)` for event-loop yielding

### One architectural concern

Analysis has a second filesystem-related debounce:

```text
0.75s
```

This should eventually be unified with the filesystem → index → analysis pipeline.

### Important conclusion

No obvious production code was found that does:

```text
sleep(...)
wait a bit...
hope another process finishes
```

without a real synchronization mechanism.

---

# Architectural Smell Summary

The biggest recurring pattern is:

```text
Bug
 ↓
Special case
 ↓
Another edge case
 ↓
Another lookup alias
 ↓
Another tokenizer
 ↓
Another fallback
```

This is concentrated in **language intelligence**, not throughout the entire application.

The long-term goal should be:

```text
Canonical RF parsing
        ↓
Canonical symbol/index model
        ↓
Context-aware resolution
        ↓
Hover / completion / diagnostics / references
```

rather than continually adding lookup-time patches.

---

# Top 10 Post-Beta Engineering Tasks

1. **Unify variable identity in the index**
2. **Create one authoritative RF cell tokenizer**
3. **Make definition ranking context-aware**
4. ~~**Align frontend/backend wildcard-tag detection**~~ ✅ done
5. ~~**Remove Insights `sole_robot` heuristic and XML budget once safe**~~ ✅ done
6. ~~**Model Create Dictionary `key=value` items properly**~~ ✅ done (varargs-only convention)
7. ~~**Handle unknown test counts safely**~~ ✅ done
8. ~~**Unify filesystem → index → analysis debounce pipeline**~~ ✅ done (watcher path)
9. ~~**Continue shrinking `AppShell`**~~ ✅ started (`GitShellController`)
10. ~~**Use real platform-specific modifier keys**~~ ✅ done

---

# Beta Decision

## Private Beta

**✅ READY**

There are:

- 0 P0 findings
- no developer-machine paths
- no silent execution bypasses
- no remaining hardcoded large-run threshold in the run path
- no major production race/timing hack identified

The remaining risks are primarily **language-intelligence correctness/maintainability**, not basic application reliability.

### Before announcing beta

- [x] Fix frontend wildcard tag detection (P1-4)
- [x] Fix `countTests` error → `0` (P2-3)
- [x] Run full regression tests (Flutter 390 passed; backend 390 passed, 1 unrelated `test_discovery_and_filtering` failure)
- [x] Use platform-specific explorer modifier keys (P3-1)
- [x] Align Create Dictionary popular-param hint with libdoc `*items` (P3-2)
- [x] Log outline analysis failures instead of swallowing them (P3-3)
- [x] Unify hover/definition/references on POST; GET is name-only compat (P3-4)
- [x] Model varargs-only `name=value` calling convention (P2-1)
- [x] Typed hover `detail_kind` (P2-6)
- [x] Remove AppShell SchedulerPhase notify deferral (P2-2)
- [ ] Verify private-beta packaging on target platforms
- [ ] Announce language intelligence as best-effort / still hardening

### After beta

- [ ] Variable identity/index model
- [ ] RF tokenizer unification
- [ ] Context-aware symbol ranking
- [ ] Insights heuristics
- [x] Create Dictionary modeling (varargs-only `name=value`)
- [ ] AppShell decomposition
- [ ] FS/index/analysis pipeline cleanup
- [x] Hover payload typing (`detail_kind`)

---

# Final Engineering Principle

For future bug fixes, ask:

> **"Am I fixing the underlying model, or am I making this exact example work?"**

Before adding:

- a special `if`
- a lookup alias
- a hardcoded string
- a fallback parser
- a delay
- a denylist
- a magic threshold
- a duplicated tokenizer

first check whether the existing abstraction can be corrected.

**Do not turn every bug report into another exception in the codebase.**

---

**Audit status:** Completed  
**Private beta status:** Pre-beta punch list done; ready to announce after packaging check  
**Next major engineering focus:** Language intelligence foundation (frozen for beta — no new special cases)
