---
title: Roadmap
description: Strategic direction for Robot Studio — beta hardening first, then semantic RF workflows that a generic editor cannot match.
---

This page is **locked product strategy**, not a release calendar and not a feature wishlist. Do not add roadmap items, panels, or beta scope here. Day-to-day rules for the current beta live in the repo’s `docs/internal/polish.md` and `docs/internal/quality.md` — those remain authoritative until freeze.

## North-star questions

1. **Can an RF SDET spend an entire week in Robot Studio without opening VS Code?**
2. **What can Robot Studio understand about an RF project that a generic editor cannot?**

Question 1 guides beta: trust the tool for a full workweek.  
Question 2 guides everything after beta: differentiate on **semantic understanding**, not on accumulating IDE chrome.

## Product Filter

Before adding anything to the active roadmap, ask:

1. Does this solve a real RF SDET problem?
2. Does it save meaningful time or prevent meaningful mistakes?
3. Does it leverage Robot Studio’s semantic understanding of tests, keywords, resources, libraries, variables, and executions?
4. Does it create a workflow that is difficult to reproduce with a generic editor + Robot Framework plugin?
5. Is it worth the complexity and maintenance cost?

If the answer to **#4** is no, it does not belong on the active post-beta roadmap — even if it would be a “nice IDE feature.”

## Strategic direction

Robot Studio already has a large surface: Editor, Tests, Execution, Reports, Libraries, Insights, Robot Doctor, Terminal, Git, Preferences, Find in Files, Find Symbol, completion, signature help, outline, and more.

The next phase is **not** more panels. It is making the **semantic foundation** produce workflows an RF SDET cannot get from VS Code + a Robot plugin.

That foundation already includes (among others):

- Keyword, parameter, and library metadata
- Document symbol trees and document analysis
- Library catalog
- Execution knowledge
- Insights
- Robot Doctor

**Direction:** Robot Studio should understand **relationships** between RF tests, keywords, resources, libraries, variables, and executions — not merely edit `.robot` files.

Use that principle to evaluate every post-beta idea.

---

## NOW — Beta Hardening

**Stage:** Private / Public Beta → trust → reliability → performance → polish → freeze.

**No feature expansion.** Interesting capabilities stay off this board.

Aligned with `docs/internal/polish.md` / `docs/internal/quality.md`:

| Focus | Meaning |
|-------|---------|
| **Trust** | Correct run targets, honest environments, no silent data loss, no identity corruption |
| **Reliability** | Open / close / restore projects safely; crashes and hung states cleared |
| **Performance** | Responsive editing and runs on real project sizes |
| **Onboarding** | First open, environment, and first run without dead ends |
| **UX / paper cuts** | Empty states, terminology, chrome consistency — polish only |
| **Release freeze** | Meet freeze criteria → Release Candidate → public beta; then release blockers only |

Success for this stage is measured by **reliability and workflow**, not features shipped.

See [What is Robot Studio?](/getting-started/overview/) for the loop that must already feel solid.

---

## NEXT — Semantic RF Workflows

After freeze, the first post-beta bet is turning semantic models into **change-aware RF workflows**.

### Candidate set (evaluated)

| Priority | Capability | Verdict |
|----------|------------|---------|
| 1 | **Impact Analysis** | Own epic — **flagship** post-beta semantic workflow; ships first |
| 2 | **Safe Rename** | Own epic — **sequenced after** Impact Analysis; distinct trust bar |
| 3 | **Callers / callees / dependency exploration** | **Not a separate product surface** — fold into Impact Analysis (and later Safe Rename previews) |

“Deeper analysis UI” as a standalone roadmap item is removed. Graph exploration that does not answer *what breaks if I change this?* is an implementation detail of Impact, not a third feature.

**Shared model rule:** Both features will consume the same canonical semantic relationship model when implementation starts. That model must **emerge from Impact Analysis requirements** — not from a speculative graph-contract spike or architecture epic.

### 1. Impact Analysis

**User problem**  
An SDET edits a shared keyword or resource and cannot tell which suites or tests will feel it — so they either over-run the suite or under-test and ship a surprise failure.

**Concrete RF workflow**  
Change (or select) a keyword / resource / variable → see **affected tests and suites** → optionally run that impact set instead of the whole project.

**Why Robot Studio today doesn’t solve it**  
Doctor and Insights describe health and composition; Find References answers “where is this name used?” They do not answer “what should I re-run after this change?” as a first-class workflow.

**Why our semantic models help**  
The analysis graph already models calls, imports, variable references, and related edges, with confidence levels and affected-tests style queries. Execution knowledge can later refine “affected” with run history — without inventing a new store first.

**Likely complexity**  
Medium–high: confidence thresholds, transitive impact, UX that stays a workflow (not a raw graph browser), and keeping results honest when the index/graph is stale.

**Own epic?**  
**Yes.** This is the flagship post-beta semantic workflow.

**Scope note**  
Callers, callees, and dependency relationships belong **inside** this epic as the explanation layer (“why is this test affected?”), not as a separate activity-bar product.

### 2. Safe Rename

**User problem**  
Renaming a keyword or variable with find-and-replace (or even naive multi-file edit) breaks callers, misses dynamic usages, or renames the wrong symbol in a large RF tree.

**Concrete RF workflow**  
Rename keyword / variable → preview references with confidence → apply only when the graph says it is safe enough → leave low-confidence hits for manual review.

**Why Robot Studio today doesn’t solve it**  
Editor rename / search-replace are text tools. They do not refuse ambiguous RF bindings.

**Why our semantic models help**  
Edges already carry confidence (`exact` / `high` / `medium` / `low`). Safe Rename should **refuse or quarantine** low-confidence hits — a behavior generic editors rarely encode for Robot Framework.

**Likely complexity**  
High: correctness over convenience; workspace-wide edits; undo/trust; variable vs keyword namespaces; resource boundaries.

**Own epic?**  
**Yes — sequenced after Impact Analysis.** It is not “Impact with a different button”; the trust bar (must not silently break callers) makes it its own epic. It reuses the relationship model that Impact Analysis made real — no separate graph-contract or architecture spike beforehand.

### 3. Callers / callees / dependency exploration — merged

Treated as **part of Impact Analysis** (and Safe Rename preview), not a third epic or panel.

| If we shipped it alone… | Why that fails the filter |
|-------------------------|---------------------------|
| Another tree/graph view | Easy to recreate partially with Find References + mental models |
| No “what do I re-run?” outcome | Weak #2 and #4 in the Product Filter |

Exploration earns its keep when it **explains impact** or **grounds a rename preview**.

---

## LATER — Execution Intelligence

After semantic change workflows are real, deepen **understanding of runs** — still outcome-driven, still RF-specific.

**Suggested order (evaluated, not assumed):**

| Order | Capability | Why this order |
|-------|------------|----------------|
| 1 | **Execution Replay** | Strongest fit to existing `output.xml` + Execution Knowledge; high SDET value without a full debug protocol |
| 2 | **Flaky-test analysis** | Builds on run history already stored; natural companion to reports / Insights |
| 3 | **Debugger** | Highest leverage long-term, but a **major epic** (runtime protocol, breakpoints, stepping, variable inspection) — not casual feature work |

### Execution Replay

**Workflow value**  
After a failure, step through what Robot actually did from the finished run — without re-running or attaching a live debugger.

**Foundation**  
`output.xml` plus Execution Knowledge already give a natural spine; graph versioning can pin which semantic snapshot a run belonged to.

**Filter**  
Hard to match in a generic editor without a purpose-built RF run browser. Worth pursuing before a live debugger.

### Flaky-test analysis

**Workflow value**  
Spot tests that flip across history so the team stops chasing one-off reds as if they were deterministic product bugs.

**Foundation**  
Run history and execution knowledge; pairs with Reports / Insights rather than a brand-new product island.

**Filter**  
Strong RF-SDET pain; depends on enough trustworthy history after beta reliability work.

### Debugger

**Workflow value**  
Pause before a keyword, step over / into / out, inspect variables, continue — the classic “I need to see live state” loop.

**Reality check**  
Treat as a **platform-sized epic**: Robot execution integration, UI chrome, and long-term maintenance. Do not schedule it as a polish-sized item or as the default first Execution Intelligence bet if Replay covers a large share of post-mortem needs sooner.

---

## PLATFORM

Directional only — not active post-beta bets until pull from real use.

| Area | Stance |
|------|--------|
| **Plugins** | Keep the capability model. Do not prioritize sandbox polish or ecosystem work until there is a concrete extension use case that cannot live as a first-party workflow. |
| **Preferences** | Ship preference changes when beta or post-beta workflows **need** them. Extra settings categories are not roadmap work. |

Removed from the strategic roadmap as standalone items: “Settings as a product feature” and undirected “plugin hardening.”

---

## LONG TERM

| Area | Stance |
|------|--------|
| **Unified Search / command surface** | A single “do / find anything” entry for commands, symbols, and files — a **workflow surface**, not “another search implementation.” Deferred until the semantic workflows above are real. |
| **Optional AI assistance** | Downstream only. AI may eventually sit on the same semantic graph; it must not substitute for Impact, Safe Rename, Replay, or a trustworthy editor loop. |

---

## Intentionally small

This roadmap is **locked** and stays short on purpose. We already have a large product. Post-beta investment should produce **differentiated RF workflows** from the semantic foundation — not more activity-bar destinations. No new roadmap items, panels, or beta scope until freeze is done and Impact Analysis is the active post-beta bet.

## Feedback

Bugs and “I wish Robot Studio could…” notes go on [GitHub Issues](https://github.com/deekshith-poojary98/robot-studio/issues). Prefer a clear RF workflow over a generic IDE wishlist. Packaged beta zips live on [GitHub Releases](https://github.com/deekshith-poojary98/robot-studio/releases).

## Next step

→ [Install Robot Studio](/getting-started/install/)
