# Robot Studio

A modern cross-platform desktop IDE for [Robot Framework](https://robotframework.org/) development.

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full design: modules, Event Bus, Plugin System, Indexing, Language Service, transport layer (REST → gRPC), and milestone plan.

**Stack:** Flutter Desktop · Python FastAPI · SQLite · Event Bus · Plugin Host · Index Store

## Prerequisites

- Flutter 3.x with desktop support (`macos`, `linux`, or `windows`)
- Python 3.11+

## Getting Started

### 1. Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
pip install -e .
python -m robot_studio.main
```

The API starts at `http://127.0.0.1:8765`. Verify with:

```bash
curl http://127.0.0.1:8765/api/v1/health
```

### 2. Frontend

In a separate terminal:

```bash
cd frontend
flutter pub get
flutter run -d macos    # or linux / windows
```

The app shell connects to the backend on launch and shows connection status in the toolbar.

## Project Structure

```
robot-studio/
├── ARCHITECTURE.md      # Design document
├── backend/             # Python FastAPI backend
│   └── robot_studio/
│       ├── api/         # HTTP routes & schemas
│       ├── application/ # Use-case services
│       ├── core/        # Config, DB, DI
│       ├── domain/      # Entities & interfaces
│       └── infrastructure/
└── frontend/            # Flutter desktop app
    └── lib/
        ├── core/        # Theme, API client
        └── presentation/ # UI shell
```

## Current Milestone

- [x] **M1** — Architecture design, app shell, backend skeleton, health API
- [x] **M1.5** — Architecture v2 (Language Service, Event Bus, Plugin System, Indexing, execution split, transport review)
- [x] **M2** — Workspace management (create/open/recent, welcome screen, explorer)
- [x] **M3** — Project management (create/import/templates, explorer, recent projects)

## Next Milestones

- **M4** — Python environment manager
- **M5** — Package manager (PackageRegistry + PipInstaller)
- **M6** — Indexing pipeline, Keyword Explorer, Language Service (completion + hover)
- **M7** — Test execution (Runner + ResultsStore), WebSocket logs, gRPC Language Service
- **M8** — Report viewer (ReportProvider), plugin manifest
- **M9** — AI plugin interface, settings, packaging

## License

TBD
