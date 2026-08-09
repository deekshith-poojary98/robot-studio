---
title: Git source control
description: Stage, commit, branch, and inspect history for the active project.
---

Git in Robot Studio is always scoped to the **active project**. It will not silently attach to a parent monorepo.

## What you can do

- See status including untracked files
- Stage changes and commit
- Switch and manage branches
- Browse history and inspect diffs
- Work with remotes when a remote exists
- **Init** a repository in the project if one does not exist yet

## Tips

- Keep `.robotstudio/` ignored (new projects get this in the seeded `.gitignore`).
- If Git looks empty or wrong, confirm the project root is the repo you intend — not a parent folder opened by mistake.
- Explorer and Test Explorer refresh from live workspace events, including Git changes from outside the app.
