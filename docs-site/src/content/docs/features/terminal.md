---
title: Terminal
description: Use the built-in project-rooted terminal for shell work beside your tests.
---

The bottom panel includes a **PTY terminal** rooted at the project folder (desktop builds only).

- Starts a login shell in the project directory
- Restart or kill from the tab chrome. **Kill** ends the current shell; choose
  **Restart** before entering more commands.
- Toggle with `⌘\`` / `Ctrl+\`` (**Terminal → Toggle Terminal**)
- Handy for one-off `robot`, `pip`, or script commands when you want the raw shell
- Opening the Terminal tab focuses the prompt. After using another control or
  menu, click inside the terminal to return keyboard input to the shell.
- Select text by dragging with the mouse. **Copy:** right-click the selection, or
  `Ctrl+Shift+C` (Windows/Linux) / `⌘C` (macOS). **Paste:** right-click with no
  selection, or `Ctrl+V` / `⌘V`.

Open a project first — without one, the tab asks you to open a project before starting a shell.

## Platform notes

- Available on **desktop** builds (macOS / Windows / Linux). Not available on web/test shells.
- Packaged **macOS** builds run **without** App Sandbox so the shell can spawn. If an older sandboxed build only prints `[process exited with code 255]`, use a current zip.
- First launch of an unsigned beta zip on macOS may be blocked by Gatekeeper — see [Install](/getting-started/install/#macos-app-blocked-after-unzip).
- **Windows:** the terminal uses Consolas (Menlo is macOS-only). After installing tools like Node, fully quit and relaunch Robot Studio so `PATH` updates apply — the in-app shell inherits the app’s environment at launch.

For installing libraries into the active Studio environment, prefer the [packages UI](/workflows/environments/) so the IDE stays in sync with what analysis and runs use.
