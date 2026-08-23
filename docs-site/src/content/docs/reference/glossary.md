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
| **Libraries** | Activity-bar browser for library keywords, docs, and arguments |
| **Packages** | Activity-bar UI to install/update/uninstall PyPI packages into the active environment |
| **Robot Doctor** | Project health findings UI (activity bar label: **Doctor**) |
| **Sidecar** | Embedded backend process started by the packaged app |
| **`.robotstudio/`** | Per-project Studio metadata, environments, reports, and run configurations |
| **`~/.robot-studio`** | Per-user app data (database, plugins, preferences) |
