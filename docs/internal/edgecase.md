Manual edge cases around durable identity, Finder deletes, packaging, and “looks fine until you dig”:

### Project / workspace lifecycle
1. **Delete in Finder → recreate same name → open** — **new** identity; no ghost envs/reports; clean “create env” toast.
2. **Delete open project → Dismiss dialog → edit & Save** — save fails with friendly “no longer on disk”; folder must **not** resurrect.
3. **Delete open project → Close → New Project same name/location** — opens fresh; toolbar shows **No environment**, not `venv · missing`.
4. **Delete open project → Locate → pick the recreated folder** — loads correctly; old tabs/git/env don’t leak.
5. **Quit app → delete project in Finder → relaunch → Recent Projects** — recent item either gone or fails with clear copy (no crash / blank shell).
6. **Rename project folder in Finder while open** — missing dialog within ~2–3s; one dialog only (not workspace + project).
7. **Move project to another parent path, reopen** — **same** identity (`.robotstudio` id); env/report paths relocate; Recent updates to new path.

### Environments
8. **Delete only `.robotstudio/environments/<venv>` while project open** — chip shows `· missing`; Run blocked; Manage still lists it until you reopen (then purge on open is OK).
9. **Create env A, activate, delete folder, Create env B same name** — succeeds; A not stuck as active ghost.
10. **Two projects, same leaf name, different parents** — env lists stay isolated (no cross-talk via name).
11. **Import / Select Existing `.venv` under project, then delete that `.venv` in Finder** — marked missing / unusable; recreate import works.
12. **Create Environment with no host Python** — “Python is not installed” + How to Install (not a dead Create).
13. **Dismiss missing-env toast** — **No environment** chip still opens Create / Manage.

### Files / Explorer
14. **Select a file → click blank Explorer → New File** — creates at project root (not under the old selection).
15. **External edit in VS Code/Cursor while Studio has file open** — reload/dirty prompt; no silent overwrite.
16. **External delete of open file** — editor notices; save doesn’t recreate unless you intend to.
17. **Case-only rename on macOS** (`tests` → `Tests`) — works; tree + open tabs stay consistent.
18. **Multi-select delete, then Esc / outside click** — selection clears; next New File goes to root.

### Run / execution trust
19. **Open project, no Robot installed** — Run disabled or blocked with Robot-missing copy (not a fake run row).
20. **Active env missing on disk** — Run blocked; no “starting…” spinner that never finishes.
21. **Start run → Stop quickly** — returns to idle; Stop disables; no stuck “Running ·”.
22. **Delete project mid-run** — stop/fail cleanly; no zombie robot process after Close.

### Packaging / process (double-click app)
23. **Quit via ⌘Q** — no orphan `robot_studio` / sidecar in Activity Monitor; relaunch works.
24. **Force-quit once, then normal launch** — reclaim orphan sidecar; health OK (no “port in use” forever).
25. **Launch packaged app, create env** — succeeds even if something deleted the backend’s original cwd (no false “RF not in env”).
26. **Data under `~/.robot-studio`** — after delete-and-recreate project, DB doesn’t keep dead env paths for that workspace.

### Git / chrome
27. **Open nested repo (project has `.git`, parent also has `.git`)** — Source Control binds to the **project** root, not the wrong parent.
28. **Non-git project** — no Fetch/Pull/Push ⋯ noise; branch chip absent/hidden.
29. **Toolbar: No environment clickable**; Tests page has **no** duplicate Run File / Run Project / Stop.

### Welcome / open model
30. **New Project while another is open** — always standalone + fresh open (tabs/tree reset); does **not** nest under the old project.
31. **Open a plain empty folder** — Continue anyways path; initializes `.robotstudio/` without wrapper dirs.
32. **Backend down on welcome** — quiet “Backend unavailable”; no endless spinner / crash.

---

**Highest value first (closest to the purge bug):** 1, 3, 5, 8, 9, 2, 23, 25.

If you want, I can turn these into a one-page checklist file in the repo.