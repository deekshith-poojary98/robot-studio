---
title: Git source control
description: Stage, commit, branch, and inspect history for the active project.
---

Git in Robot Studio is always scoped to the **active project**. It will not silently attach to a parent monorepo.

## Present (beta)

| Capability | Where |
|------------|--------|
| Init repository in the project | Source Control empty state |
| Working-tree status (including untracked) | Changes list; header chip shows **Pending changes** or **Up to date** |
| Select files + commit all / commit selected | Commit panel |
| View file diff | Diff tab (click a change); syntax highlighting matches the editor; scroll horizontally and vertically |
| Resize Changes list | Drag the divider between Changes and Diff / History |
| Commit history + commit detail | History tab |
| Switch / create / delete local branches | Branch control in Source Control header (and toolbar) |
| Add / edit remote URL (`origin`) | **Add remote** in the Source Control header strip |
| Set / change Git author name and email | **Set identity** / **Change** in the Source Control header (prompted on first commit if missing) |
| Fetch / Pull / Push | Header icons (and toolbar ⋯) once a remote exists |
| Refresh status | Header refresh |

## Missing / limited (beta)

| Gap | Notes |
|-----|--------|
| Create GitHub/GitLab repo from Studio | Create the empty repo on the host, then paste its URL |
| Clone from URL | Open an existing project folder instead |
| Ahead/behind counts vs upstream | Not shown yet |
| Stage vs unstage as separate lists | Selection + commit selected covers a simple flow |
| Discard / restore file | Not in UI yet |
| Merge / rebase / stash / conflict UI | Not available |
| Auth / credential helper UI | Relies on system Git credentials |

**Push after Init:** use **Add remote**, paste your GitHub/GitLab URL, then **Push**. The first push sets upstream automatically when needed.

## Tips

- Keep `.robotstudio/` ignored (new projects get this in the seeded `.gitignore`).
- If Git looks empty or wrong, confirm the project root is the repo you intend — not a parent folder opened by mistake.
- Explorer and Tests refresh from live workspace events, including Git changes from outside the app.
- History shows the **commit author** (Git `user.name`), not the project name. Use **Set identity** if name and email are missing, or **Change** to update them. Existing commits keep the author they were created with.
