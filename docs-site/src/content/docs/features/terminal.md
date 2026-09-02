---
title: Terminal
description: Use the built-in project-rooted terminal for shell work beside your tests.
---

The bottom panel includes a **PTY terminal** rooted at the project folder (desktop builds only).

- Starts a login shell in the project directory
- Restart or kill from the tab chrome
- Toggle with `⌘\`` / `Ctrl+\`` (**Terminal → Toggle Terminal**)
- Handy for one-off `robot`, `pip`, or script commands when you want the raw shell

Open a project first — without one, the tab asks you to open a project before starting a shell.

## Platform notes

- Available on **desktop** builds (macOS / Windows / Linux). Not available on web/test shells.
- Packaged **macOS** builds run **without** App Sandbox so the shell can spawn. If an older sandboxed build only prints `[process exited with code 255]`, use a current zip.
- First launch of an unsigned beta zip on macOS may be blocked by Gatekeeper — see [Install](/getting-started/install/#macos-app-blocked-after-unzip).

For installing libraries into the active Studio environment, prefer the [packages UI](/workflows/environments/) so the IDE stays in sync with what analysis and runs use.
