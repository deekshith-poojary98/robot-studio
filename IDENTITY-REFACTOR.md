# Durable project identity — audit & migration plan

**Status:** Implemented (2026-08-04)  
**Goal:** Eliminate path-derived identity. Paths are locations; identity lives on disk under `.robotstudio/`.

---

## Approved decisions (locked)

1. **Migrate-on-read** — no version bump, no separate migration tool. Missing `workspace.json` id → mint/persist immediately (standalone: reuse `project.json` id when present).
2. **Move/rename** — persisted id is source of truth; update stored path; remove stale registry/recent rows for old paths.
3. **Purge helpers** — keep as artifact hygiene (not identity).
4. **Classic** — same durable workspace id rules; do **not** preserve old `uuid5` history.

---

## Target architecture

| Mode | Identity | Persistence |
|---|---|---|
| Standalone | `workspace.id == project.id` | `.robotstudio/workspace.json` + `project.json` |
| Classic | Distinct workspace + per-project ids | `workspace.json.id` + each `project.json.id` |

**Rule:** Persistent identity comes from `.robotstudio`, never from the filesystem path.

---

## SQLite table ownership

Database: `~/.robot-studio/robot-studio.db`

| Table | Primary ownership | Path role | Notes / fix in this refactor |
|---|---|---|---|
| `workspaces` | **workspace identity** (PK `id`) | Current location (`UNIQUE`) | Upsert by **id**; delete other rows claiming same path; update path on move |
| `recent_workspaces` | **workspace identity** (`workspace_id`) | Recent location (PK `path` for UX) | On record: delete prior rows for same `workspace_id`; path is bookmark only |
| `projects` | **project identity** (PK `id`) + `workspace_id` FK | Current location (`UNIQUE`) | Upsert by **id**; stale path rows cleared |
| `recent_projects` | **project identity** (`project_id`) | Recent location (PK `path`) | On record: delete prior rows for same `project_id` |
| `environments` | **workspace identity** + env `id` (PK) | Venv location (`UNIQUE`) | Upsert by **id** (was wrongly path-conflict overwriting id); relocate paths on move before purge |
| `execution_runs` | **workspace** + **project** ids | Artifact dirs (`output_dir`, html paths) | Location only; relocate on move before purge |
| `index_symbols` | **workspace** + **project** | `file_path` content key | Path is file location for symbols (not project identity); rebuild after moves as needed |
| `index_files` | **workspace** + **project** | PK `file_path` (mtime cache) | Path = file location cache — OK |
| `index_references` | **project** | file paths in rows | Location |
| `index_meta` | neither (meta keys) | — | OK |
| `analysis_entities` | **project** (+ workspace col) | path in entity payload / hash | Content addressing — out of scope for product identity |
| `analysis_edges` | **project** | — | OK |
| `analysis_meta` | **project** (key suffix) | — | OK |
| `analysis_cache` | **project** | — | OK |
| `execution_entity_stats` | **project** | — | OK |
| `execution_history` | **project** | — | OK |
| `execution_edges` | **project** | — | OK |
| `execution_linked_runs` | **project** | — | OK |
| `doctor_reports` | **project** | — | OK |
| `schema_version` | neither | — | OK |

**Recent `path` PKs:** kept as location bookmarks for the welcome screen. They are **not** product identity. Identity columns travel with the row; move clears old path bookmarks for that id.

---

## What changed in code

- Removed `uuid5` / `workspace_id_for_path` from production.
- `workspace.json` persists `id`; create/init always write it; open migrate-on-read.
- Standalone: `project.id` forced equal to `workspace.id` on create/import/ensure.
- Repositories upsert by durable id; path updated; stale path/recent cleaned.
- Env/report path relocate on `WorkspaceOpened` before missing-artifact purge.
- `register_in_workspace` preserves `workspace.json` id when rewriting projects[].

---

## Success criteria coverage

| # | Scenario | Covered by |
|---|---|---|
| 1 | Create → reopen → same id | `test_open_workspace_success`, project API reopen |
| 2–3 | Rename/move → same id | `test_durable_id_survives_folder_move` |
| 4 | Delete + recreate same name → new id | `test_recreate_same_path_mints_new_workspace_id`, env recreate test |
| 5 | Classic still works | existing workspace/project tests |
| 6 | No path-derived identity | `rg uuid5` clean under `robot_studio/` |

---

## Out of scope (deferred)

Copy detection, clone collision dialogs, fingerprinting, generation counters.
