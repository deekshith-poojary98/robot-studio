---
title: Your first project
description: Create or open a Robot Framework project and activate an environment.
---

Robot Studio is project-first. Environments, packages, runs, and Git all scope to the **active project**.

## Create a new project

1. On the welcome screen, choose **New Project** (or use the File menu).
2. Pick a folder location and name.
3. Robot Studio seeds empty `tests/`, `resources/`, and `variables/` folders plus a sensible `.gitignore`.
4. Studio metadata lives in `.robotstudio/` inside the project (ignored by the seeded gitignore).

You do not pick a “template type” — every new project is a plain Robot Framework folder ready to fill in.

## Open an existing project

1. Choose **Open Project**.
2. Select any folder that already contains Robot Framework files.
3. Robot Studio will use that folder in place and create `.robotstudio/` as needed.

**Recent Projects** on the welcome screen is the fastest way back to work you already opened.

:::tip[Workspaces]
Workspaces are an advanced multi-project container (Open / New / Recent). Most people can ignore them at first and work with a single project.
:::

## Set up an environment

Tests run inside a Python environment that has Robot Framework (and your libraries) installed.

1. Open **Manage Environments** from the toolbar or project flow.
2. **Create**, **import**, or **clone** an environment, then **activate** it.
3. Studio-managed venvs live under `.robotstudio/environments/`. Existing `.venv` / `venv` / `env` folders are also discovered.

If you open a project without an active environment, Robot Studio prompts you — you can continue editing, but runs need an environment.

## Install packages (optional)

From the packages UI you can:

- See what is already installed
- Search PyPI
- Install, update, or uninstall libraries into the active environment

## Next step

→ [Run your first tests](/getting-started/first-run/)
