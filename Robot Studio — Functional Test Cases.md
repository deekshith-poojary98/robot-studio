# Robot Studio — Functional Test Cases


| Field                  | Value                                                          |
| ---------------------- | -------------------------------------------------------------- |
| **Product**            | Robot Studio (Flutter desktop + FastAPI backend)               |
| **Version under test** | v0.1.0 (public beta)                                           |
| **Author stance**      | Manual QA / functional tester                                  |
| **Platform**           | Desktop only (`macos` / `linux` / `windows`) — not Flutter web |
| **Backend**            | `http://127.0.0.1:8765`                                        |
| **Date**               | 2026-07-25                                                     |


---

## How to use

1. Start backend, then frontend (`flutter run -d macos` or equivalent).
2. Use a clean disposable workspace for destructive cases; keep a known-good fixture (e.g. `robot-files` with project + env) for happy path.
3. Mark each case **Pass / Fail / Blocked / N/A** and note build + OS in the execution log.
4. Priority: **P0** = smoke / release gate · **P1** = core functional · **P2** = polish / edge.

**Standard result columns (add in your tracker):** `Status` · `Actual` · `Bug ID` · `Tester` · `Date`

---



## Test data prerequisites


| ID    | Data                                                  | Notes               |
| ----- | ----------------------------------------------------- | ------------------- |
| TD-01 | Empty folder (no `.robot-studio` / no projects)       | New workspace flows |
| TD-02 | Existing workspace with ≥1 project + active env       | Happy path          |
| TD-03 | Workspace that is **not** a Git repo                  | Git empty state     |
| TD-04 | Workspace that **is** a Git repo with remotes         | Fetch/Pull/Push     |
| TD-05 | `.robot` file with valid + invalid keywords           | Editor / Problems   |
| TD-06 | Project that imports a missing library (e.g. Browser) | Install guidance    |
| TD-07 | Backend stopped / port blocked                        | Offline UX          |


---



## Module index


| Module                                  | Prefix | Count   | P0     |
| --------------------------------------- | ------ | ------- | ------ |
| 1. Shell / Status / Connectivity        | SH     | 8       | 4      |
| 2. Workspace                            | WS     | 10      | 4      |
| 3. Project                              | PR     | 10      | 4      |
| 4. Explorer / Files                     | EX     | 8       | 3      |
| 5. Environment                          | EN     | 10      | 4      |
| 6. Packages                             | PK     | 9       | 3      |
| 7. Editor                               | ED     | 10      | 4      |
| 8. Language / Problems                  | LG     | 10      | 4      |
| 9. Indexing / Keywords / Search / Tests | IX     | 10      | 3      |
| 10. Command palette                     | CP     | 7       | 3      |
| 11. Execution                           | XC     | 12      | 5      |
| 12. Reports                             | RP     | 9       | 4      |
| 13. Git / Source Control                | GT     | 10      | 3      |
| 14. Plugins                             | PL     | 7       | 2      |
| 15. UX guidance & gating                | UX     | 8       | 4      |
| 16. Cross-cutting / regression          | XR     | 6       | 2      |
| **Total**                               |        | **144** | **56** |


---



## 1. Shell / Status / Connectivity



### SH-01 — Cold start with backend up


|                   |                                                                                           |
| ----------------- | ----------------------------------------------------------------------------------------- |
| **Priority**      | P0                                                                                        |
| **Preconditions** | Backend healthy; no stale UI session                                                      |
| **Steps**         | 1. Launch app. 2. Observe toolbar + status bar + welcome.                                 |
| **Expected**      | Status shows **CONNECTED** (not READY). Welcome visible. No crash. Idle run badge hidden. |




### SH-02 — Cold start with backend down


|                   |                                                                                                                      |
| ----------------- | -------------------------------------------------------------------------------------------------------------------- |
| **Priority**      | P0                                                                                                                   |
| **Preconditions** | Backend not running                                                                                                  |
| **Steps**         | 1. Launch app. 2. Observe chrome.                                                                                    |
| **Expected**      | Status **OFFLINE**. App remains usable for welcome; actions that need API show guidance / fail gracefully (no hang). |




### SH-03 — Backend reconnect


|                   |                                                |
| ----------------- | ---------------------------------------------- |
| **Priority**      | P1                                             |
| **Preconditions** | App open while offline                         |
| **Steps**         | 1. Start backend. 2. Wait / interact.          |
| **Expected**      | Status flips to **CONNECTED** without restart. |




### SH-04 — Status bar ROBOT / PYTHON + toolbar env


|                   |                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------- |
| **Priority**      | P0                                                                                       |
| **Preconditions** | TD-02 with active env (Robot installed)                                                  |
| **Steps**         | 1. Open workspace. 2. Activate env. 3. Read toolbar + status bar.                        |
| **Expected**      | Toolbar shows env name; status bar `ROBOT` / `PYTHON` show versions (not `—`). No `ENV` in status bar. |




### SH-05 — Status bar ERRORS / WARNINGS shortcut


|                   |                                                                       |
| ----------------- | --------------------------------------------------------------------- |
| **Priority**      | P1                                                                    |
| **Preconditions** | Open `.robot` with known diagnostics                                  |
| **Steps**         | 1. Wait for diagnostics. 2. Click ERRORS (or WARNINGS) in status bar. |
| **Expected**      | Bottom **Problems** panel opens/reveals; counts match list.           |




### SH-06 — Activity rail tooltips


|                   |                                                                                  |
| ----------------- | -------------------------------------------------------------------------------- |
| **Priority**      | P2                                                                               |
| **Preconditions** | App open                                                                         |
| **Steps**         | Hover each activity rail icon (Explorer, Tests, Keywords, Packages, Reports, …). |
| **Expected**      | Descriptive tooltips (not bare single words only).                               |




### SH-07 — View switching does not stick previous empty state


|                   |                                                                                                          |
| ----------------- | -------------------------------------------------------------------------------------------------------- |
| **Priority**      | P0                                                                                                       |
| **Preconditions** | TD-02                                                                                                    |
| **Steps**         | 1. Open Source Control (empty or git). 2. Switch to Reports. 3. Switch to Packages. 4. Back to Explorer. |
| **Expected**      | Each view shows its own content; no leftover empty-state from prior view in main pane.                   |




### SH-08 — Bottom panel tabs


|                   |                                                                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **Priority**      | P1                                                                                                                                       |
| **Preconditions** | Workspace open                                                                                                                           |
| **Steps**         | Open Console / Problems / Execution Logs (as available). Collapse / expand.                                                              |
| **Expected**      | Tabs switch; collapse does not hide critical welcome CTAs permanently after reopen; Terminal shows milestone placeholder if not shipped. |


---



## 2. Workspace



### WS-01 — Create new workspace


|                   |                                                                                   |
| ----------------- | --------------------------------------------------------------------------------- |
| **Priority**      | P0                                                                                |
| **Preconditions** | TD-01 empty folder available                                                      |
| **Steps**         | 1. New Workspace. 2. Pick folder / confirm. 3. Observe shell.                     |
| **Expected**      | Workspace opens; name in toolbar; Explorer scoped to folder; recent list updated. |




### WS-02 — Open existing workspace


|                   |                                                          |
| ----------------- | -------------------------------------------------------- |
| **Priority**      | P0                                                       |
| **Preconditions** | TD-02                                                    |
| **Steps**         | Welcome → Open Workspace → select folder.                |
| **Expected**      | Opens successfully; projects/envs load; no error dialog. |




### WS-02b — Open Project (folder picker)


|                   |                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------- |
| **Priority**      | P0                                                                                       |
| **Preconditions** | Any Robot Framework project folder (inside or outside a Studio workspace)                |
| **Steps**         | Welcome → Open Project → select the project folder.                                      |
| **Expected**      | Project opens immediately; no “not inside a workspace” error. Studio metadata is created silently when needed. |




### WS-03 — Open from Recent Workspaces


|                   |                                                            |
| ----------------- | ---------------------------------------------------------- |
| **Priority**      | P0                                                         |
| **Preconditions** | At least one recent workspace                              |
| **Steps**         | From welcome, click a Recent Workspace. Hover for tooltip. |
| **Expected**      | Opens that path; tooltip shows full path.                  |




### WS-04 — Recent Projects without workspace


|                   |                                                                                      |
| ----------------- | ------------------------------------------------------------------------------------ |
| **Priority**      | P0                                                                                   |
| **Preconditions** | Recent projects exist; no workspace open                                             |
| **Steps**         | Click a Recent Project from welcome.                                                 |
| **Expected**      | Auto-opens owning workspace via project path and selects the project; no modal gate. |




### WS-05 — Welcome CTAs gated without workspace


|                   |                                                                        |
| ----------------- | ---------------------------------------------------------------------- |
| **Priority**      | P0                                                                     |
| **Preconditions** | No workspace                                                           |
| **Steps**         | Observe Create Project / Manage Environments.                          |
| **Expected**      | Disabled (or guidance on click); not a silent no-op that looks broken. |




### WS-06 — Create Project enabled after open


|                   |                                                         |
| ----------------- | ------------------------------------------------------- |
| **Priority**      | P1                                                      |
| **Preconditions** | Workspace just opened                                   |
| **Steps**         | Check welcome / toolbar CTAs.                           |
| **Expected**      | Create / Import / Manage Environments become available. |




### WS-07 — Switch workspace


|                   |                                                                               |
| ----------------- | ----------------------------------------------------------------------------- |
| **Priority**      | P1                                                                            |
| **Preconditions** | Two workspaces in recent                                                      |
| **Steps**         | Open A, then Open B (or recent B).                                            |
| **Expected**      | Context switches fully (tree, env, project selection); no mixed paths from A. |




### WS-08 — Invalid / inaccessible path


|                   |                                                                              |
| ----------------- | ---------------------------------------------------------------------------- |
| **Priority**      | P2                                                                           |
| **Preconditions** | Deleted folder still in recent (if possible)                                 |
| **Steps**         | Open deleted recent workspace.                                               |
| **Expected**      | Clear error; app remains stable; recent can be ignored/removed if supported. |




### WS-09 — Cancel folder picker


|                   |                                     |
| ----------------- | ----------------------------------- |
| **Priority**      | P2                                  |
| **Preconditions** | —                                   |
| **Steps**         | Open Workspace → cancel picker.     |
| **Expected**      | No crash; previous state unchanged. |




### WS-10 — Workspace name in chrome


|                   |                                            |
| ----------------- | ------------------------------------------ |
| **Priority**      | P2                                         |
| **Preconditions** | TD-02                                      |
| **Steps**         | Confirm toolbar workspace label.           |
| **Expected**      | Shows workspace name (not “No workspace”). |


---



## 3. Project



### PR-01 — Create project


|                   |                                                                                |
| ----------------- | ------------------------------------------------------------------------------ |
| **Priority**      | P0                                                                             |
| **Preconditions** | Workspace open (or welcome New Project / standalone)                           |
| **Steps**         | New Project → enter name → create.                                             |
| **Expected**      | Project appears in list/explorer; empty `tests/` / `resources/` / `variables/`; details show path (no type/template). |




### PR-02 — Duplicate project name


|                   |                                         |
| ----------------- | --------------------------------------- |
| **Priority**      | P1                                      |
| **Preconditions** | Project “Amazon” exists                 |
| **Steps**         | Create another project named Amazon.    |
| **Expected**      | Validation error; no corrupt duplicate. |




### PR-03 — Empty / invalid project name


|                   |                                                         |
| ----------------- | ------------------------------------------------------- |
| **Priority**      | P1                                                      |
| **Preconditions** | New Project dialog open                                 |
| **Steps**         | Submit empty name; try illegal characters if UI allows. |
| **Expected**      | Blocked with clear validation.                          |




### PR-04 — Import existing project tree


|                   |                                                              |
| ----------------- | ------------------------------------------------------------ |
| **Priority**      | P0                                                           |
| **Preconditions** | Folder with Robot suite outside (or inside) workspace policy |
| **Steps**         | Import Project → select folder → confirm.                    |
| **Expected**      | Project registered; files reachable in Explorer.             |




### PR-05 — Open / select project


|                   |                                                              |
| ----------------- | ------------------------------------------------------------ |
| **Priority**      | P0                                                           |
| **Preconditions** | ≥2 projects                                                  |
| **Steps**         | Select project A then B.                                     |
| **Expected**      | Details panel updates; Run Project targets selected project. |




### PR-06 — Auto-select project on workspace open


|                   |                                                          |
| ----------------- | -------------------------------------------------------- |
| **Priority**      | P1                                                       |
| **Preconditions** | TD-02 with recent project                                |
| **Steps**         | Open workspace.                                          |
| **Expected**      | A project is auto-selected when possible (recent/first). |




### PR-07 — Project details accuracy


|                   |                                          |
| ----------------- | ---------------------------------------- |
| **Priority**      | P1                                       |
| **Preconditions** | Known project                            |
| **Steps**         | Open details; compare path/type/created. |
| **Expected**      | Metadata matches disk/backend.           |




### PR-08 — Cancel create / import


|                   |                                 |
| ----------------- | ------------------------------- |
| **Priority**      | P2                              |
| **Preconditions** | Dialog open                     |
| **Steps**         | Cancel mid-flow.                |
| **Expected**      | No partial project left behind. |




### PR-09 — Project without environment — Run gated


|                   |                                                                       |
| ----------------- | --------------------------------------------------------------------- |
| **Priority**      | P0                                                                    |
| **Preconditions** | Project selected; no active env                                       |
| **Steps**         | Click Run / Run Project.                                              |
| **Expected**      | Guidance to create/activate environment; run does not start silently. |




### PR-10 — Open project from Explorer

| Field             | Detail                                                       |
|-------------------|--------------------------------------------------------------|
| **ID**            | PR-10                                                        |
| **Title**         | Open project from Explorer after workspace open              |
| **Priority**      | P2                                                           |
| **Preconditions** | Workspace open, project listed                               |
| **Steps**         | Open a project from the Explorer (no “Continue with …” CTA). |
| **Expected**      | Lands in useful context (explorer/editor), not empty shell.  |


---



## 4. Explorer / Files



### EX-01 — File tree lists project suites


|                   |                                                                       |
| ----------------- | --------------------------------------------------------------------- |
| **Priority**      | P0                                                                    |
| **Preconditions** | TD-02 with `tests/*.robot`                                            |
| **Steps**         | Open Explorer; expand project.                                        |
| **Expected**      | Suite files visible (e.g. `sample.robot`); not only project metadata. |




### EX-02 — Open file from tree


|                   |                                            |
| ----------------- | ------------------------------------------ |
| **Priority**      | P0                                         |
| **Preconditions** | Suite file visible                         |
| **Steps**         | Click `.robot` file.                       |
| **Expected**      | Editor tab opens with content; path shown. |




### EX-03 — site-packages not flooding tree


|                   |                                                                                     |
| ----------------- | ----------------------------------------------------------------------------------- |
| **Priority**      | P1                                                                                  |
| **Preconditions** | Env with packages installed                                                         |
| **Steps**         | Expand Environments / venv if present.                                              |
| **Expected**      | Deep `site-packages` noise collapsed/hidden by default (or clearly out of the way). |




### EX-04 — Multi-file tabs


|                   |                                                      |
| ----------------- | ---------------------------------------------------- |
| **Priority**      | P1                                                   |
| **Preconditions** | ≥2 files                                             |
| **Steps**         | Open two files; switch tabs.                         |
| **Expected**      | Content switches correctly; dirty state independent. |




### EX-05 — Close tab with unsaved changes


|                   |                                                      |
| ----------------- | ---------------------------------------------------- |
| **Priority**      | P0                                                   |
| **Preconditions** | Edited unsaved file                                  |
| **Steps**         | Close tab.                                           |
| **Expected**      | Prompt to save / discard / cancel; cancel keeps tab. |




### EX-06 — Save / Save All


|                   |                                                             |
| ----------------- | ----------------------------------------------------------- |
| **Priority**      | P1                                                          |
| **Preconditions** | Dirty buffers                                               |
| **Steps**         | Save active; Save All.                                      |
| **Expected**      | Dirty markers clear; disk updated; status message if shown. |




### EX-07 — External file change


|                   |                                                                                  |
| ----------------- | -------------------------------------------------------------------------------- |
| **Priority**      | P2                                                                               |
| **Preconditions** | File open in editor                                                              |
| **Steps**         | Edit same file outside app; return to app.                                       |
| **Expected**      | Reload prompt or consistent reload behavior; no silent data loss without notice. |




### EX-08 — Non-robot file open (if allowed)


|                   |                                               |
| ----------------- | --------------------------------------------- |
| **Priority**      | P2                                            |
| **Preconditions** | `.txt` / `.resource` in tree                  |
| **Steps**         | Open file.                                    |
| **Expected**      | Opens or clear unsupported message; no crash. |


---



## 5. Environment



### EN-01 — Create environment


|                   |                                                                |
| ----------------- | -------------------------------------------------------------- |
| **Priority**      | P0                                                             |
| **Preconditions** | Workspace open                                                 |
| **Steps**         | Manage Environments → Create → name → confirm.                 |
| **Expected**      | Env appears; can activate; Robot/Python eventually detectable. |




### EN-02 — Activate environment


|                   |                                                                |
| ----------------- | -------------------------------------------------------------- |
| **Priority**      | P0                                                             |
| **Preconditions** | ≥1 env                                                         |
| **Steps**         | Activate env from manager or toolbar switcher.                 |
| **Expected**      | Toolbar + status bar update to that env; packages/runs use it. |




### EN-03 — Switch between environments


|                   |                                           |
| ----------------- | ----------------------------------------- |
| **Priority**      | P1                                        |
| **Preconditions** | ≥2 envs                                   |
| **Steps**         | Activate A then B.                        |
| **Expected**      | Package list and Robot version reflect B. |




### EN-04 — Import environment


|                   |                                 |
| ----------------- | ------------------------------- |
| **Priority**      | P1                              |
| **Preconditions** | Existing venv path              |
| **Steps**         | Import Environment flow.        |
| **Expected**      | Env registered and activatable. |




### EN-05 — Clone environment


|                   |                                         |
| ----------------- | --------------------------------------- |
| **Priority**      | P1                                      |
| **Preconditions** | Source env exists                       |
| **Steps**         | Clone → new name.                       |
| **Expected**      | New env created; independent of source. |




### EN-06 — Delete environment


|                   |                                               |
| ----------------- | --------------------------------------------- |
| **Priority**      | P1                                            |
| **Preconditions** | Disposable env                                |
| **Steps**         | Delete with confirmation.                     |
| **Expected**      | Removed from list; cannot activate afterward. |




### EN-07 — Delete active environment


|                   |                                                                            |
| ----------------- | -------------------------------------------------------------------------- |
| **Priority**      | P1                                                                         |
| **Preconditions** | Active disposable env                                                      |
| **Steps**         | Delete while active.                                                       |
| **Expected**      | Clear confirmation; chrome returns to “No environment” or switches safely. |




### EN-08 — Duplicate env name


|                   |                         |
| ----------------- | ----------------------- |
| **Priority**      | P2                      |
| **Preconditions** | Env “myenv” exists      |
| **Steps**         | Create another “myenv”. |
| **Expected**      | Validation error.       |




### EN-09 — Cancel create/import


|                   |                 |
| ----------------- | --------------- |
| **Priority**      | P2              |
| **Preconditions** | Dialog open     |
| **Steps**         | Cancel.         |
| **Expected**      | No partial env. |




### EN-10 — Manage Environments without workspace


|                   |                                                  |
| ----------------- | ------------------------------------------------ |
| **Priority**      | P0                                               |
| **Preconditions** | No workspace                                     |
| **Steps**         | Attempt Manage Environments.                     |
| **Expected**      | Disabled or guidance dialog with primary action. |


---



## 6. Packages



### PK-01 — List installed packages


|                   |                                                            |
| ----------------- | ---------------------------------------------------------- |
| **Priority**      | P0                                                         |
| **Preconditions** | Active env with packages                                   |
| **Steps**         | Open Package Manager.                                      |
| **Expected**      | Installed list loads (includes robotframework if present). |




### PK-02 — Search PyPI


|                   |                                       |
| ----------------- | ------------------------------------- |
| **Priority**      | P1                                    |
| **Preconditions** | Network available; env active         |
| **Steps**         | Search e.g. `robotframework-browser`. |
| **Expected**      | Results appear; no uncaught error.    |




### PK-03 — Install package


|                   |                                                          |
| ----------------- | -------------------------------------------------------- |
| **Priority**      | P0                                                       |
| **Preconditions** | Active env; package not installed                        |
| **Steps**         | Install a small package; wait for progress.              |
| **Expected**      | Progress UI; success; package appears in installed list. |




### PK-04 — Update package


|                   |                                                         |
| ----------------- | ------------------------------------------------------- |
| **Priority**      | P1                                                      |
| **Preconditions** | Installed package with update available (if detectable) |
| **Steps**         | Update.                                                 |
| **Expected**      | Completes or clear “up to date”; list refreshes.        |




### PK-05 — Uninstall package


|                   |                                                           |
| ----------------- | --------------------------------------------------------- |
| **Priority**      | P1                                                        |
| **Preconditions** | Disposable package installed                              |
| **Steps**         | Uninstall with confirm.                                   |
| **Expected**      | Removed from list; confirm prevents accidental uninstall. |




### PK-06 — Install without active env


|                   |                                              |
| ----------------- | -------------------------------------------- |
| **Priority**      | P0                                           |
| **Preconditions** | No active env                                |
| **Steps**         | Open packages / attempt install.             |
| **Expected**      | Guidance to activate env; no opaque failure. |




### PK-07 — Offline / PyPI failure


|                   |                                  |
| ----------------- | -------------------------------- |
| **Priority**      | P2                               |
| **Preconditions** | Network disabled (if testable)   |
| **Steps**         | Search / install.                |
| **Expected**      | User-visible error; UI recovers. |




### PK-08 — Package details panel


|                   |                                            |
| ----------------- | ------------------------------------------ |
| **Priority**      | P2                                         |
| **Preconditions** | Package selected                           |
| **Steps**         | Open details.                              |
| **Expected**      | Name/version/actions consistent with list. |




### PK-09 — Missing-library install from run failure


|                   |                                                            |
| ----------------- | ---------------------------------------------------------- |
| **Priority**      | P1                                                         |
| **Preconditions** | TD-06 project; env without Browser                         |
| **Steps**         | Run project → observe failure snackbar/CTA → Install.      |
| **Expected**      | Prompt to install missing library; install path reachable. |


---



## 7. Editor



### ED-01 — Open and edit `.robot` content


|                   |                                              |
| ----------------- | -------------------------------------------- |
| **Priority**      | P0                                           |
| **Preconditions** | Suite file                                   |
| **Steps**         | Open; type text; observe dirty.              |
| **Expected**      | Edits accepted; dirty indicator; undo works. |




### ED-02 — Find / replace


|                   |                                              |
| ----------------- | -------------------------------------------- |
| **Priority**      | P1                                           |
| **Preconditions** | File with known string                       |
| **Steps**         | Find; replace one; replace all if available. |
| **Expected**      | Matches highlight; replace updates buffer.   |




### ED-03 — Outline / document symbols


|                   |                                           |
| ----------------- | ----------------------------------------- |
| **Priority**      | P1                                        |
| **Preconditions** | Suite with keywords/tests                 |
| **Steps**         | Open outline if present; click symbol.    |
| **Expected**      | Navigates to definition location in file. |




### ED-04 — Multi-tab dirty independence


|                   |                               |
| ----------------- | ----------------------------- |
| **Priority**      | P1                            |
| **Preconditions** | Two open files                |
| **Steps**         | Edit only tab A; switch to B. |
| **Expected**      | Only A dirty; B pristine.     |




### ED-05 — Save keyboard / menu path


|                   |                                         |
| ----------------- | --------------------------------------- |
| **Priority**      | P0                                      |
| **Preconditions** | Dirty file                              |
| **Steps**         | Save via UI and/or palette “Save File”. |
| **Expected**      | Persists; dirty clears.                 |




### ED-06 — Large file responsiveness


|                   |                                                      |
| ----------------- | ---------------------------------------------------- |
| **Priority**      | P2                                                   |
| **Preconditions** | Large `.robot` if available                          |
| **Steps**         | Open; scroll; type.                                  |
| **Expected**      | Usable (no multi-second freezes for typical suites). |




### ED-07 — Jump to line:column from Problems


|                   |                                      |
| ----------------- | ------------------------------------ |
| **Priority**      | P0                                   |
| **Preconditions** | Diagnostic at known line/col         |
| **Steps**         | Click problem row.                   |
| **Expected**      | Caret lands at reported line/column. |




### ED-08 — Reopen recent file


|                   |                                       |
| ----------------- | ------------------------------------- |
| **Priority**      | P1                                    |
| **Preconditions** | Recently opened files                 |
| **Steps**         | Open via palette recent or UI recent. |
| **Expected**      | Correct file opens.                   |




### ED-09 — Syntax / section headers display


|                   |                                                             |
| ----------------- | ----------------------------------------------------------- |
| **Priority**      | P2                                                          |
| **Preconditions** | Standard Robot sections                                     |
| **Steps**         | Visually inspect `*** Settings *`** / `*** Test Cases ***`. |
| **Expected**      | Readable formatting; no layout corruption.                  |




### ED-10 — Close all / last tab


|                   |                                                  |
| ----------------- | ------------------------------------------------ |
| **Priority**      | P2                                               |
| **Preconditions** | Multiple tabs                                    |
| **Steps**         | Close until none remain.                         |
| **Expected**      | Empty editor state clean; can open another file. |


---



## 8. Language intelligence / Problems



### LG-01 — Live diagnostics on edit


|                   |                                                                         |
| ----------------- | ----------------------------------------------------------------------- |
| **Priority**      | P0                                                                      |
| **Preconditions** | Env + index usable; open suite                                          |
| **Steps**         | Introduce unknown keyword; wait.                                        |
| **Expected**      | Problem appears; ERRORS count increments; Problems panel can auto-open. |




### LG-02 — Fix clears diagnostic


|                   |                              |
| ----------------- | ---------------------------- |
| **Priority**      | P0                           |
| **Preconditions** | Error present                |
| **Steps**         | Fix keyword; wait.           |
| **Expected**      | Problem clears; counts drop. |




### LG-03 — Completions


|                   |                                           |
| ----------------- | ----------------------------------------- |
| **Priority**      | P1                                        |
| **Preconditions** | Indexed keywords / BuiltIn                |
| **Steps**         | Type partial keyword; trigger completion. |
| **Expected**      | Suggestions include relevant keywords.    |




### LG-04 — Hover


|                   |                                                           |
| ----------------- | --------------------------------------------------------- |
| **Priority**      | P1                                                        |
| **Preconditions** | Known keyword                                             |
| **Steps**         | Hover keyword.                                            |
| **Expected**      | Hover info (signature/docs) or graceful empty — no crash. |




### LG-05 — Go to definition


|                   |                                   |
| ----------------- | --------------------------------- |
| **Priority**      | P1                                |
| **Preconditions** | User keyword defined in workspace |
| **Steps**         | Go to definition on usage.        |
| **Expected**      | Jumps to definition file/line.    |




### LG-06 — Find references


|                   |                                   |
| ----------------- | --------------------------------- |
| **Priority**      | P2                                |
| **Preconditions** | Keyword used in multiple places   |
| **Steps**         | Find references.                  |
| **Expected**      | List of usages; navigation works. |




### LG-07 — Problems empty state


|                   |                                                                              |
| ----------------- | ---------------------------------------------------------------------------- |
| **Priority**      | P2                                                                           |
| **Preconditions** | Clean valid file                                                             |
| **Steps**         | Open Problems.                                                               |
| **Expected**      | Clear empty state (not stuck old errors from other file unless intentional). |




### LG-08 — Problems location label format


|                   |                                                      |
| ----------------- | ---------------------------------------------------- |
| **Priority**      | P1                                                   |
| **Preconditions** | ≥1 problem                                           |
| **Steps**         | Read location text.                                  |
| **Expected**      | Basename + line + column (e.g. `sample.robot:12:5`). |




### LG-09 — Collapsed Problems count


|                   |                                         |
| ----------------- | --------------------------------------- |
| **Priority**      | P1                                      |
| **Preconditions** | N problems                              |
| **Steps**         | Collapse bottom panel header.           |
| **Expected**      | Shows problems count (e.g. PROBLEMS N). |




### LG-10 — Language without env


|                   |                                                    |
| ----------------- | -------------------------------------------------- |
| **Priority**      | P2                                                 |
| **Preconditions** | No active env                                      |
| **Steps**         | Edit file; observe diagnostics/completions.        |
| **Expected**      | Degraded but explained behavior — no freeze/crash. |


---



## 9. Indexing / Keywords / Search / Tests



### IX-01 — Index status card


|                   |                                                               |
| ----------------- | ------------------------------------------------------------- |
| **Priority**      | P1                                                            |
| **Preconditions** | Workspace open                                                |
| **Steps**         | Open Keywords / Search area showing index status.             |
| **Expected**      | Status READY/building with counts (files/libraries/keywords). |




### IX-02 — Rebuild index


|                   |                                                 |
| ----------------- | ----------------------------------------------- |
| **Priority**      | P0                                              |
| **Preconditions** | Workspace with suites                           |
| **Steps**         | Rebuild Index; wait.                            |
| **Expected**      | Completes; counts update; no permanent spinner. |




### IX-03 — Keyword search finds BuiltIn


|                   |                                        |
| ----------------- | -------------------------------------- |
| **Priority**      | P0                                     |
| **Preconditions** | Index ready                            |
| **Steps**         | Search `Log` in Keywords/Search.       |
| **Expected**      | BuiltIn `Log` (or equivalent) appears. |




### IX-04 — Workspace symbol search


|                   |                                               |
| ----------------- | --------------------------------------------- |
| **Priority**      | P1                                            |
| **Preconditions** | User keywords in project                      |
| **Steps**         | Search for a user keyword name.               |
| **Expected**      | Symbol listed with file path; open navigates. |




### IX-05 — Empty search query


|                   |                              |
| ----------------- | ---------------------------- |
| **Priority**      | P2                           |
| **Preconditions** | Search page open             |
| **Steps**         | Clear query.                 |
| **Expected**      | Sensible empty/prompt state. |




### IX-06 — Tests panel lists suites


|                   |                                             |
| ----------------- | ------------------------------------------- |
| **Priority**      | P0                                          |
| **Preconditions** | TD-02 with suites on disk                   |
| **Steps**         | Open Tests panel.                           |
| **Expected**      | Suites listed (not empty when files exist). |




### IX-07 — Open suite from Tests panel


|                   |                                                      |
| ----------------- | ---------------------------------------------------- |
| **Priority**      | P1                                                   |
| **Preconditions** | Suite listed                                         |
| **Steps**         | Select/open suite.                                   |
| **Expected**      | Opens in editor or focuses run target appropriately. |




### IX-08 — Index after new file


|                   |                                                             |
| ----------------- | ----------------------------------------------------------- |
| **Priority**      | P1                                                          |
| **Preconditions** | Index ready                                                 |
| **Steps**         | Add new `.robot` with keyword; rebuild or wait incremental. |
| **Expected**      | New symbols discoverable.                                   |




### IX-09 — Search page vs palette


|                   |                                                                      |
| ----------------- | -------------------------------------------------------------------- |
| **Priority**      | P2                                                                   |
| **Preconditions** | Workspace open                                                       |
| **Steps**         | Sidebar Search → full Search page. Palette → Search Symbols command. |
| **Expected**      | Both reach searchable symbols; roles distinct.                       |




### IX-10 — Keywords 0 investigation gate


|                   |                                                                                 |
| ----------------- | ------------------------------------------------------------------------------- |
| **Priority**      | P1                                                                              |
| **Preconditions** | Project with Settings Library BuiltIn + keywords                                |
| **Steps**         | Rebuild; check keyword count.                                                   |
| **Expected**      | Keywords count > 0 for typical fixtures; if 0, log as defect with fixture path. |


---



## 10. Command palette



### CP-01 — Open via ⌘K / Ctrl+K


|                   |                                      |
| ----------------- | ------------------------------------ |
| **Priority**      | P0                                   |
| **Preconditions** | App focused                          |
| **Steps**         | Press ⌘K (macOS) or Ctrl+K.          |
| **Expected**      | Palette dialog opens; input focused. |




### CP-02 — Open via toolbar search chrome


|                   |                                                              |
| ----------------- | ------------------------------------------------------------ |
| **Priority**      | P0                                                           |
| **Preconditions** | —                                                            |
| **Steps**         | Click toolbar search field.                                  |
| **Expected**      | Same palette (commands/files/symbols), not only Search page. |




### CP-03 — Filter commands


|                   |                                                   |
| ----------------- | ------------------------------------------------- |
| **Priority**      | P0                                                |
| **Preconditions** | Palette open                                      |
| **Steps**         | Type `run` / `env` / `report`.                    |
| **Expected**      | Matching commands remain; unrelated filtered out. |




### CP-04 — Activate with Enter / click


|                   |                               |
| ----------------- | ----------------------------- |
| **Priority**      | P1                            |
| **Preconditions** | Filtered list                 |
| **Steps**         | Arrow keys; Enter; or click.  |
| **Expected**      | Command runs; palette closes. |




### CP-05 — File search


|                   |                                                                |
| ----------------- | -------------------------------------------------------------- |
| **Priority**      | P1                                                             |
| **Preconditions** | Workspace + file tree loaded                                   |
| **Steps**         | Type suite filename.                                           |
| **Expected**      | File result; open loads editor. site-packages noise minimized. |




### CP-06 — Symbol search in palette


|                   |                                         |
| ----------------- | --------------------------------------- |
| **Priority**      | P1                                      |
| **Preconditions** | Index ready                             |
| **Steps**         | Type keyword/symbol name.               |
| **Expected**      | Symbol results; open jumps to location. |




### CP-07 — Esc closes


|                   |                              |
| ----------------- | ---------------------------- |
| **Priority**      | P2                           |
| **Preconditions** | Palette open                 |
| **Steps**         | Press Esc.                   |
| **Expected**      | Closes without side effects. |


---



## 11. Execution



### XC-01 — Run current file (happy path)


|                   |                                                               |
| ----------------- | ------------------------------------------------------------- |
| **Priority**      | P0                                                            |
| **Preconditions** | Project + env + valid suite open                              |
| **Steps**         | Run (file).                                                   |
| **Expected**      | Status running; logs stream; ends Pass/Fail; history updated. |




### XC-02 — Run project


|                   |                                                        |
| ----------------- | ------------------------------------------------------ |
| **Priority**      | P0                                                     |
| **Preconditions** | TD-02                                                  |
| **Steps**         | Run Project.                                           |
| **Expected**      | Executes selected project; live logs; terminal status. |




### XC-03 — Stop execution


|                   |                                                  |
| ----------------- | ------------------------------------------------ |
| **Priority**      | P0                                               |
| **Preconditions** | Long-running suite (or sleep keyword)            |
| **Steps**         | Start run → Stop.                                |
| **Expected**      | Process stops; status not stuck Running forever. |




### XC-04 — Stop muted when idle


|                   |                                                  |
| ----------------- | ------------------------------------------------ |
| **Priority**      | P1                                               |
| **Preconditions** | Idle                                             |
| **Steps**         | Observe Stop control.                            |
| **Expected**      | Visually muted / inactive — not looking “armed”. |




### XC-05 — Run + Run Project primary styling


|                   |                                     |
| ----------------- | ----------------------------------- |
| **Priority**      | P2                                  |
| **Preconditions** | Gated actions available             |
| **Steps**         | Compare Run vs Run Project buttons. |
| **Expected**      | Both primary-styled consistently.   |




### XC-06 — Run without workspace


|                   |                            |
| ----------------- | -------------------------- |
| **Priority**      | P0                         |
| **Preconditions** | No workspace               |
| **Steps**         | Attempt Run.               |
| **Expected**      | Guidance dialog; no crash. |




### XC-07 — Run without project


|                   |                                    |
| ----------------- | ---------------------------------- |
| **Priority**      | P0                                 |
| **Preconditions** | Workspace, no project selected     |
| **Steps**         | Attempt Run Project.               |
| **Expected**      | Guidance to create/select project. |




### XC-08 — Execution logs reveal


|                   |                                                   |
| ----------------- | ------------------------------------------------- |
| **Priority**      | P1                                                |
| **Preconditions** | After a run                                       |
| **Steps**         | Click run status badge (`Last: Failed` / Passed). |
| **Expected**      | Opens Execution Logs with that run output.        |




### XC-09 — Cold start idle (no stale run)


|                   |                                              |
| ----------------- | -------------------------------------------- |
| **Priority**      | P0                                           |
| **Preconditions** | Prior run existed; restart app               |
| **Steps**         | Launch app; read execution status.           |
| **Expected**      | Idle / no fake “Running”; badge Idle hidden. |




### XC-10 — Concurrent run blocked


|                   |                                                               |
| ----------------- | ------------------------------------------------------------- |
| **Priority**      | P1                                                            |
| **Preconditions** | Run in progress                                               |
| **Steps**         | Click Run again.                                              |
| **Expected**      | Blocked or queued with message — not two conflicting runners. |




### XC-11 — Failed run preserves artifacts paths in logs


|                   |                                                   |
| ----------------- | ------------------------------------------------- |
| **Priority**      | P1                                                |
| **Preconditions** | TD-06 failure                                     |
| **Steps**         | Run; read logs.                                   |
| **Expected**      | Failure reason visible; report paths if produced. |




### XC-12 — History list


|                   |                                           |
| ----------------- | ----------------------------------------- |
| **Priority**      | P1                                        |
| **Preconditions** | ≥2 runs                                   |
| **Steps**         | Open execution history / reports history. |
| **Expected**      | Newest first; statuses correct.           |


---



## 12. Reports



### RP-01 — Reports list after run


|                   |                                                       |
| ----------------- | ----------------------------------------------------- |
| **Priority**      | P0                                                    |
| **Preconditions** | Completed run                                         |
| **Steps**         | Open Reports rail panel.                              |
| **Expected**      | Run appears under Recent (not “No reports yet” when API has runs). No duplicate Recent Runs column on the main page. |




### RP-02 — Auto-select latest run


|                   |                                       |
| ----------------- | ------------------------------------- |
| **Priority**      | P0                                    |
| **Preconditions** | ≥1 run                                |
| **Steps**         | Open Reports (rail).                  |
| **Expected**      | Latest run selected; main view shows details (dashboard + artifacts). |




### RP-03 — Open report.html via artifact hyperlink


|                   |                                                       |
| ----------------- | ----------------------------------------------------- |
| **Priority**      | P0                                                    |
| **Preconditions** | Run with `report.html`                                |
| **Steps**         | In Artifacts, click **report.html**.                  |
| **Expected**      | File opens in the system default app; snackbar if shown. |




### RP-04 — Open log.html via artifact hyperlink


|                   |                         |
| ----------------- | ----------------------- |
| **Priority**      | P0                      |
| **Preconditions** | Run with `log.html`     |
| **Steps**         | In Artifacts, click **log.html**. |
| **Expected**      | File opens in the system default app. |




### RP-05 — Clickable artifacts (xml / log / report)


|                   |                            |
| ----------------- | -------------------------- |
| **Priority**      | P1                         |
| **Preconditions** | Artifacts listed           |
| **Steps**         | Click `output.xml`, `log.html`, `report.html` names. |
| **Expected**      | Each opens; no separate Open Log / Open Report buttons. |




### RP-06 — Pass/fail dashboard stats


|                   |                                 |
| ----------------- | ------------------------------- |
| **Priority**      | P1                              |
| **Preconditions** | Mix of passed/failed runs       |
| **Steps**         | View reports dashboard/summary. |
| **Expected**      | Counts match history.           |




### RP-07 — Delete run


|                   |                                      |
| ----------------- | ------------------------------------ |
| **Priority**      | P1                                   |
| **Preconditions** | Disposable run                       |
| **Steps**         | Delete with confirm.                 |
| **Expected**      | Removed from list; confirm required. |




### RP-08 — Reports with zero runs


|                   |                              |
| ----------------- | ---------------------------- |
| **Priority**      | P2                           |
| **Preconditions** | Fresh workspace              |
| **Steps**         | Open Reports.                |
| **Expected**      | Clear empty state; no crash. |




### RP-09 — Switch away and back after new run


|                   |                                           |
| ----------------- | ----------------------------------------- |
| **Priority**      | P1                                        |
| **Preconditions** | Reports open                              |
| **Steps**         | Run project; return to Reports (or stay). |
| **Expected**      | List refreshes to include new run.        |


---



## 13. Git / Source Control



### GT-01 — Non-repo empty state


|                   |                                                |
| ----------------- | ---------------------------------------------- |
| **Priority**      | P0                                             |
| **Preconditions** | TD-03                                          |
| **Steps**         | Open Source Control.                           |
| **Expected**      | Clear “Not a Git repository” + Initialize CTA. |




### GT-02 — Initialize repository


|                   |                                                       |
| ----------------- | ----------------------------------------------------- |
| **Priority**      | P0                                                    |
| **Preconditions** | TD-03                                                 |
| **Steps**         | Initialize Git Repository.                            |
| **Expected**      | Status view appears; branch shown (e.g. main/master). |




### GT-03 — Status / changed files


|                   |                                       |
| ----------------- | ------------------------------------- |
| **Priority**      | P1                                    |
| **Preconditions** | Repo; modify a tracked/untracked file |
| **Steps**         | Refresh Source Control.               |
| **Expected**      | Changes listed.                       |




### GT-04 — Stage / unstage


|                   |                                    |
| ----------------- | ---------------------------------- |
| **Priority**      | P1                                 |
| **Preconditions** | Changes present                    |
| **Steps**         | Stage file(s).                     |
| **Expected**      | Moves to staged; unstage reverses. |




### GT-05 — Commit


|                   |                                                        |
| ----------------- | ------------------------------------------------------ |
| **Priority**      | P0                                                     |
| **Preconditions** | Staged changes                                         |
| **Steps**         | Enter message → Commit.                                |
| **Expected**      | Commit succeeds; working tree clean (for those files). |




### GT-06 — Empty commit message blocked


|                   |                            |
| ----------------- | -------------------------- |
| **Priority**      | P1                         |
| **Preconditions** | Staged changes             |
| **Steps**         | Commit with empty message. |
| **Expected**      | Blocked with validation.   |




### GT-07 — Branch list / switch (local)


|                   |                                            |
| ----------------- | ------------------------------------------ |
| **Priority**      | P1                                         |
| **Preconditions** | ≥2 local branches                          |
| **Steps**         | Switch branch.                             |
| **Expected**      | Branch label updates; tree matches branch. |




### GT-08 — History / diff


|                   |                            |
| ----------------- | -------------------------- |
| **Priority**      | P1                         |
| **Preconditions** | Commits exist              |
| **Steps**         | Open history; open a diff. |
| **Expected**      | Diff readable; no crash.   |




### GT-09 — Remote actions gated when no remotes / no repo


|                   |                                                            |
| ----------------- | ---------------------------------------------------------- |
| **Priority**      | P0                                                         |
| **Preconditions** | TD-03 or repo without remotes                              |
| **Steps**         | Observe Fetch / Pull / Push.                               |
| **Expected**      | Hidden or disabled with reason — not active dead controls. |




### GT-10 — Fetch / Pull / Push with remotes


|                   |                                                    |
| ----------------- | -------------------------------------------------- |
| **Priority**      | P1                                                 |
| **Preconditions** | TD-04; network                                     |
| **Steps**         | Fetch; Pull; Push (safe branch).                   |
| **Expected**      | Operations complete or show actionable Git errors. |


---



## 14. Plugins



### PL-01 — Plugin manager lists builtins


|                   |                                                   |
| ----------------- | ------------------------------------------------- |
| **Priority**      | P0                                                |
| **Preconditions** | Backend connected                                 |
| **Steps**         | Open Plugin Manager.                              |
| **Expected**      | Builtin plugins listed (installer, runner, etc.). |




### PL-02 — No layout overflow on rows


|                   |                                               |
| ----------------- | --------------------------------------------- |
| **Priority**      | P1                                            |
| **Preconditions** | Plugin list visible                           |
| **Steps**         | Visually inspect rows at default window size. |
| **Expected**      | No yellow/black overflow stripes.             |




### PL-03 — Enable / Disable exclusivity


|                   |                                                        |
| ----------------- | ------------------------------------------------------ |
| **Priority**      | P0                                                     |
| **Preconditions** | Toggleable plugin                                      |
| **Steps**         | Enable then Disable (or reverse).                      |
| **Expected**      | Only one of Enable/Disable shown; state badge matches. |




### PL-04 — Builtin Enable not dead control


|                   |                                           |
| ----------------- | ----------------------------------------- |
| **Priority**      | P1                                        |
| **Preconditions** | Builtin already enabled                   |
| **Steps**         | Inspect row actions.                      |
| **Expected**      | No disabled Enable next to ENABLED badge. |




### PL-05 — Plugin details panel


|                   |                                           |
| ----------------- | ----------------------------------------- |
| **Priority**      | P1                                        |
| **Preconditions** | Plugin selected                           |
| **Steps**         | Open details.                             |
| **Expected**      | Name/status/actions consistent with list. |




### PL-06 — Reload plugins (if exposed)


|                   |                           |
| ----------------- | ------------------------- |
| **Priority**      | P2                        |
| **Preconditions** | Reload action available   |
| **Steps**         | Reload.                   |
| **Expected**      | List refreshes; no crash. |




### PL-07 — Plugins offline


|                   |                                    |
| ----------------- | ---------------------------------- |
| **Priority**      | P2                                 |
| **Preconditions** | Backend down                       |
| **Steps**         | Open Plugin Manager.               |
| **Expected**      | Error/empty with message; no hang. |


---



## 15. UX guidance & gating



### UX-01 — Missing workspace guidance


|                   |                                                                    |
| ----------------- | ------------------------------------------------------------------ |
| **Priority**      | P0                                                                 |
| **Preconditions** | No workspace                                                       |
| **Steps**         | Trigger gated action (New Project, Run, Packages, …).              |
| **Expected**      | Dialog with primary CTA (Open/Create workspace), not dead OK-only. |




### UX-02 — Missing project guidance


|                   |                                      |
| ----------------- | ------------------------------------ |
| **Priority**      | P0                                   |
| **Preconditions** | Workspace, no project                |
| **Steps**         | Run Project / project-scoped action. |
| **Expected**      | Guidance to create/import project.   |




### UX-03 — Missing environment guidance


|                   |                                          |
| ----------------- | ---------------------------------------- |
| **Priority**      | P0                                       |
| **Preconditions** | Workspace + project; no env              |
| **Steps**         | Run.                                     |
| **Expected**      | Guidance to manage/activate environment. |




### UX-04 — Recent item tooltips


|                   |                            |
| ----------------- | -------------------------- |
| **Priority**      | P2                         |
| **Preconditions** | Recent workspaces/projects |
| **Steps**         | Hover names.               |
| **Expected**      | Full path tooltip.         |




### UX-05 — Coming-soon stubs honest


|                   |                                                     |
| ----------------- | --------------------------------------------------- |
| **Priority**      | P1                                                  |
| **Preconditions** | —                                                   |
| **Steps**         | Open Terminal (and any stub panels).                |
| **Expected**      | Explicit milestone message — not blank broken pane. |




### UX-06 — AI entry points absent


|                   |                                                                    |
| ----------------- | ------------------------------------------------------------------ |
| **Priority**      | P1                                                                 |
| **Preconditions** | —                                                                  |
| **Steps**         | Scan chrome for AI assistant.                                      |
| **Expected**      | No AI surface until product ships AIProvider (or clearly stubbed). |




### UX-07 — Failed badge clickable


|                   |                              |
| ----------------- | ---------------------------- |
| **Priority**      | P0                           |
| **Preconditions** | Last run Failed              |
| **Steps**         | Click `Last: Failed` badge.  |
| **Expected**      | Navigates to execution logs. |




### UX-08 — Welcome hierarchy


|                   |                                                                              |
| ----------------- | ---------------------------------------------------------------------------- |
| **Priority**      | P1                                                                           |
| **Preconditions** | Cold start; console open                                                     |
| **Steps**         | Observe Recent Workspaces vs Recent Projects visibility.                     |
| **Expected**      | Workspaces discoverable (not buried under console); projects don’t dead-end. |


---



## 16. Cross-cutting / regression



### XR-01 — Full happy path smoke


|                   |                                                                                            |
| ----------------- | ------------------------------------------------------------------------------------------ |
| **Priority**      | P0                                                                                         |
| **Preconditions** | Clean machine session                                                                      |
| **Steps**         | Connect → open workspace → select project → activate env → open suite → run → open report. |
| **Expected**      | End-to-end success path in < reasonable time; no blocking UX traps.                        |




### XR-02 — Rapid panel switching stress


|                   |                                       |
| ----------------- | ------------------------------------- |
| **Priority**      | P1                                    |
| **Preconditions** | TD-02                                 |
| **Steps**         | Click activity icons rapidly for 30s. |
| **Expected**      | No freeze; final panel correct.       |




### XR-03 — Window resize


|                   |                                                                      |
| ----------------- | -------------------------------------------------------------------- |
| **Priority**      | P2                                                                   |
| **Preconditions** | —                                                                    |
| **Steps**         | Resize to narrow then wide.                                          |
| **Expected**      | Toolbar/search degrade gracefully (hint hides); no overflow stripes. |




### XR-04 — Long session memory / leak smoke


|                   |                                               |
| ----------------- | --------------------------------------------- |
| **Priority**      | P2                                            |
| **Preconditions** | —                                             |
| **Steps**         | Run 5 times; open many files; leave 15 min.   |
| **Expected**      | Remains responsive; no runaway CPU when idle. |




### XR-05 — Backend restart mid-session


|                   |                                                           |
| ----------------- | --------------------------------------------------------- |
| **Priority**      | P1                                                        |
| **Preconditions** | Workspace open                                            |
| **Steps**         | Kill backend; restart; continue.                          |
| **Expected**      | Reconnect; user can re-open/continue without app restart. |




### XR-06 — Locale / special characters in names


|                   |                                                    |
| ----------------- | -------------------------------------------------- |
| **Priority**      | P2                                                 |
| **Preconditions** | —                                                  |
| **Steps**         | Create project/env with spaces/unicode if allowed. |
| **Expected**      | Accepted or validated; paths remain usable.        |


---



## Suggested execution sets


| Suite                    | Cases        | When              |
| ------------------------ | ------------ | ----------------- |
| **Smoke (release gate)** | All P0       | Every build       |
| **Core regression**      | P0 + P1      | Weekly / pre-beta |
| **Full functional**      | All          | Milestone / RC    |
| **Git remotes**          | GT-09, GT-10 | Only with TD-04   |
| **Install guidance**     | PK-09, XC-11 | With TD-06        |


---



## Defect logging template

```
Title: [Module] short symptom
Build / OS:
Case ID:
Steps:
Expected:
Actual:
Severity: Blocker / Critical / Major / Minor / Trivial
Attachments: screenshot, logs, report path
```

---



## Traceability (product areas → modules)


| Product feature (README)    | Test modules |
| --------------------------- | ------------ |
| Workspaces                  | WS, UX, SH   |
| Projects                    | PR, EX, UX   |
| Environments                | EN, SH, UX   |
| Packages                    | PK           |
| Editor                      | ED, LG       |
| Language / Problems         | LG           |
| Command palette             | CP           |
| Indexing / Keywords / Tests | IX           |
| Execution                   | XC           |
| Reports                     | RP           |
| Git                         | GT           |
| Plugins                     | PL           |
| Status / chrome             | SH, UX       |


