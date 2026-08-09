---
title: Settings reference
description: Environment variables and paths that configure Robot Studio.
---

Backend settings use the `ROBOT_STUDIO_` prefix.

| Variable | Default | Meaning |
|----------|---------|---------|
| `ROBOT_STUDIO_HOST` | `127.0.0.1` | Bind address |
| `ROBOT_STUDIO_PORT` | `8765` | HTTP / WebSocket port |
| `ROBOT_STUDIO_DATA_DIR` | `~/.robot-studio` | SQLite DB, plugins, local data |
| `ROBOT_STUDIO_DEBUG` | `false` | Debug mode |
| `ROBOT_STUDIO_LARGE_RUN_THRESHOLD` | `100` | Confirm before project/tag runs larger than this many tests |
| `ROBOT_STUDIO_CONTENT_SEARCH_EXTENSIONS` | `.robot,.resource,.py,.yaml,.yml,.txt,.md,.json,.tsv,.csv` | File suffixes scanned by Find in Files |

Database path: `{data_dir}/robot-studio.db`.

Integration and packaging notes for contributors live in the repository README and `frontend/integration_test/README.md`.
