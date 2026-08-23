---
title: Environments & packages
description: Create or import a Python environment and install Robot libraries from PyPI.
---

Robot Framework needs a Python environment with `robotframework` and your libraries. Robot Studio manages that environment per project.

## Environments

From **Manage Environments…** you can:

| Action | Use when |
|--------|----------|
| **Create** | You want a fresh Studio-managed venv |
| **Import** | You already have a venv elsewhere |
| **Clone** | You want a copy of an existing environment |
| **Activate** | You want runs and language features to use that env |

Studio-managed environments live under `.robotstudio/environments/`. Legacy `Environments/` folders and common local names (`.venv`, `venv`, `env`) are still discovered. Choosing **Use** on a detected `.venv` registers it as `venv` (leading dots are stripped from the display name).

The status bar shows **ROBOT** and **PYTHON** versions from the active environment so you can confirm you are on the stack you expect. Creating or importing an environment also shows a short confirmation in the status bar.

## Packages

With an environment active:

1. Open the **Packages** activity-bar rail.
2. Browse installed packages or search PyPI.
3. Install, update, or uninstall as needed.

This is the usual path for libraries such as `robotframework-seleniumlibrary`, `robotframework-browser`, and project-specific packages.

## Health tips

- If completions or diagnostics look wrong after switching environments, wait for indexing to settle, then reopen the file.
- Missing imports often show up in both the Problems panel and [Robot Doctor](/features/robot-doctor/).
- Prefer one clearly activated environment per project so runs and analysis stay aligned.
