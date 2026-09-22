# Robot Studio 1.1.0 — Planned features & improvements

**Status:** Ready to cut (M4 harden complete)  
**Theme:** First post-beta **semantic RF workflow** — not more IDE chrome.  
**North star:** What breaks / what should I re-run if I change this keyword, resource, or variable?

Aligned with the public [Roadmap](../../docs-site/src/content/docs/getting-started/roadmap.md) (**NEXT — Semantic RF Workflows**). This file is the working checklist for the 1.1.0 cut; update checkboxes as work lands.

---

## Goals

1. Ship **Impact Analysis** as a first-class workflow an RF SDET cannot get from VS Code + a Robot plugin.
2. Keep the product trustworthy (correct impact, honest confidence, no silent wrong targets).
3. Fold callers / dependency explanation **into** Impact — do not add a new activity-bar panel.
4. Leave **Safe Rename**, Replay, Flaky, Debugger, and AI for later releases.

---

## Must ship (1.1.0)

### 1. Impact Analysis (flagship)

**User problem**  
Edit a shared keyword / resource / variable → unclear which suites or tests are affected → over-run the whole project or under-test and ship a surprise failure.

**Workflow**

1. Select (or caret on) a keyword, resource import, or variable.
2. Open **Impact Analysis** (command palette + context/menu entry).
3. See **affected tests and suites**, with a short “why” (direct call, transitive call, import, variable use).
4. Optionally **Run impact set** (same execution path as today’s run configs / Tests tree — no silent wrong target).
5. Jump to any listed file / test from the result list.

**Acceptance**

- [x] Impact from **user keyword** (same file + other resources) — `POST /analysis/graph/impact` (M1)
- [x] Impact from **Resource** import path — seed resolve + reverse `IMPORTS_RESOURCE` + suite→test expand
- [x] Impact from **variable** (where graph confidence allows) — reverse `REFERENCES_VARIABLE`
- [x] Results distinguish **direct** vs **transitive** (or equivalent clear labeling) — `relation` + `depth`
- [x] Low-confidence / unresolved hits are labeled — never presented as certain — `items` vs `uncertain`
- [x] Stale index / graph: clear empty or warning state; no fabricated edges — `empty_graph` / empty seeds
- [x] **Run affected** executes only the listed tests/suites (manual + automated coverage) — **Run Impact Set** via `runSelectedTests` (certain hits)
- [x] Works on a mid-size real project without freezing the UI — async HTTP + `asyncio.to_thread` BFS + `deque`
- [x] User guide page + keyboard/command entry documented — `workflows/impact-analysis.md`, Go menu, command palette

**Out of scope for this epic (do not sneak in)**

- Standalone call-hierarchy / dependency-graph product surface
- Safe Rename apply/preview as a separate epic
- AI “explain this change”
- Live debugger

### 2. Shared relationship model (only as needed by Impact)

Impact consumes the existing analysis / indexing graph. Improve the model **only where Impact requirements force it**.

- [x] Document which edge types Impact uses (call, import, …) — reverse `CALLS` + `IMPORTS_RESOURCE` + `REFERENCES_VARIABLE`
- [x] Confidence thresholds for “include in impact set” vs “show as uncertain” — `LOW` → `uncertain`
- [x] Refresh / invalidate behavior when files change while the Impact view is open — `INDEX_UPDATED` re-query (debounced)

No speculative graph-contract rewrite without an Impact user story.

### 3. Run-affected integration

- [x] Reuse existing run pipeline (env, run config tags/vars, Stop, reports) — `POST /tests/run-selected`
- [x] Empty impact set → no run; clear message
- [x] Large impact set → same large-run confirmation threshold as today

---

## Should ship (if schedule allows)

Polish that makes Impact trustworthy or clears 1.0 paper cuts that block daily RF work — still **≤ short tasks**, not new products.

| Item | Why in 1.1.0 | Status |
|------|----------------|--------|
| Command palette: **Impact Analysis** / **Run Impact Set** | Discoverability | Done |
| Go menu entries | Same | Done |
| Empty / loading / stale states for Impact panel | Trust | Done (empty graph, no hits, refresh on index) |
| Docs: workflow page under `docs-site` workflows | keep-user-guide-updated | Done |
| Context menu on keyword name / resource cell | Same | Deferred (Go + palette sufficient for cut) |
| Tester-reported **P0/P1 bugs** that affect open → edit → run | Reliability | As reported |

Optional small improvements (drop if they threaten the cut):

- [ ] Explorer / outline paper cuts still open in `docs/internal/polish.md` P1
- [ ] Package Manager install loading / naming polish
- [ ] Clearer “Backend unavailable” when port allocation fails after retries

---

## Explicitly not in 1.1.0

| Item | Target instead |
|------|----------------|
| **Safe Rename** (preview + confidence-gated apply) | 1.2.0+ (own epic after Impact) |
| **Execution Replay** | Later — Execution Intelligence |
| **Flaky-test analysis** | Later |
| **Debugger** | Later — platform-sized epic |
| **Plugins** activity bar / ecosystem | Until a concrete first-party gap |
| **AI assistance** | Downstream of semantic workflows |
| Git stash / merge / rebase UI | Not a 1.1.0 bet |
| Notarized macOS / installers | Distribution track, not this feature cut |

---

## Suggested milestones

| Milestone | Outcome | Status |
|-----------|---------|--------|
| **M1 — Query** | Given a symbol, return affected tests/suites with confidence + why | Done |
| **M2 — UI** | Impact results view + jump-to-source + empty/stale states | Done |
| **M3 — Run** | Run impact set through existing execution path | Done |
| **M4 — Harden** | Tests, docs, beta smoke; versions `1.1.0`; tag `v1.1.0` | Ready (tag pending push) |

Version rule remains: **release tag = backend `robot_studio.__version__`** (now `1.1.0`).

### M4 cut checklist

- [x] Backend `__version__` / `pyproject.toml` → `1.1.0`
- [x] Flutter `pubspec.yaml` → `1.1.0+6`; Windows fallback string
- [x] Health / architecture tests expect `1.1.0`
- [x] `RELEASE_NOTES.md` describes Impact in tester language
- [x] User guide: Impact workflow + homepage card + roadmap note
- [x] Automated smoke: analysis engine + architecture + menu bar tests
- [ ] Manual smoke on a real suite (before / after tagging):
  1. Open mid-size RF project; wait for index
  2. Caret on shared keyword → Impact → jump + Run Impact Set
  3. Caret on `Resource …` path → Impact shows importers’ tests
  4. Caret on `${VAR}` → Impact (or uncertain) honestly
  5. Save a related file with panel open → results refresh
  6. Confirm UI stays responsive during Impact on that suite
- [ ] Commit cut artifacts → push branch → tag **`v1.1.0`** (triggers Package Desktop)

---

## Success criteria

1. An SDET can change a shared keyword and, without leaving Robot Studio, see and re-run the affected tests.
2. Impact never silently claims certainty for low-confidence bindings.
3. No new top-level product island that duplicates Find References without a “what do I re-run?” outcome.
4. `RELEASE_NOTES.md` for 1.1.0 describes Impact Analysis in tester language; user guide has a workflow page.

---

## References

- Public strategy: `docs-site/src/content/docs/getting-started/roadmap.md`
- Beta polish / deferred: `docs/internal/polish.md`
- Feature brainstorm (context only): `docs/internal/feature-category.md`
