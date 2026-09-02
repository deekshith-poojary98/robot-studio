---
title: Glossary
description: Short definitions for Robot Studio and Robot Framework terms used in this guide.
---

| Term | Meaning |
|------|---------|
| **Project** | A Robot Framework folder you open or create; the primary unit of work |
| **Open Project** | Opens a folder as its own Studio session (the usual path) |
| **Import Project** | Adds an existing folder into an already-open **multi-project workspace** — not the same as Open Project |
| **Workspace** | Optional multi-project container; advanced |
| **Environment** | A Python virtualenv used for analysis, packages, and runs |
| **Active environment** | The environment currently selected for the project |
| **Run configuration** | Named execution context (tags, variables, optional per-run environment pin) selected next to **Run / Project / Stop**. Does not switch the active environment. Stored in `.robotstudio/run-configurations.json` |
| **Index** | Background database of keywords, variables (Variables section, `VAR`, arguments, assignments, FOR), and files for search and navigation |
| **Tests** | Activity-bar tree of suites and tests you can run |
| **Failed Tests** | List of failures after a run (Execution / Reports) with Jump to Source and Re-run Test |
| **Find in Files** | Text search across the project (Search rail / `⌘⇧F`) |
| **Libraries** | Activity-bar browser of **BuiltIn** plus libraries imported with `Library` in `.robot` / `.resource` files |
| **Packages** | Activity-bar UI to install/update/uninstall PyPI packages into the active environment |
| **Insights** | Run-health triage and index composition view |
| **Robot Doctor** | Project health findings UI (activity bar label: **Doctor**) — structural issues only |
| **Settings** | Full-screen preferences UI (activity-bar gear, File → Settings…, `⌘,`) stored in `~/.robot-studio/settings.json` |
| **Sidecar** | Embedded backend process started by the packaged app |
| **`.robotstudio/`** | Per-project Studio metadata, environments, reports, and run configurations |
| **`~/.robot-studio`** | Per-user app data (database, Settings, plugins data, logs) |
