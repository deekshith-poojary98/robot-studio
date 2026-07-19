You are a senior software architect and desktop application engineer.

I want to build a modern cross-platform desktop application called "Robot Studio" (working name). This is a passion project intended to become the best development environment for Robot Framework users.

This is NOT a generic code editor like VS Code or PyCharm. Instead, it is a Robot Framework-focused workspace with an excellent developer experience.

## Vision

Think of it as:
- PyCharm's polished UX
- VS Code's extensibility
- Robot Framework specific workflows
- Beautiful modern UI

The goal is to remove the need for terminals and manual configuration wherever possible.

---

## Core Features

### Workspace
- Create/Open Workspace
- Multiple Robot projects
- Workspace settings
- Shared resources
- Shared variables
- Shared keywords

### Project Management
- Create project from templates
- Open existing Robot projects
- Project explorer
- File explorer
- Test explorer

### Python Environment Manager
- Create virtual environments
- Delete virtual environments
- Rename environments
- Select active environment
- Detect installed Python versions
- Create environments using selected Python version

### Package Manager
UI similar to VS Code Extensions.

Features:
- Search packages from PyPI
- Install package
- Update package
- Uninstall package
- Show installed version
- Show latest version
- Package documentation
- Package dependencies

Everything should happen through the UI.

No terminal required.

### Robot Library Manager
Automatically detect installed Robot libraries.

Display:
- Library name
- Version
- Documentation
- Keywords
- Keyword arguments
- Examples
- Source file

### Keyword Explorer
Global search for keywords.

Selecting a keyword should show:
- Documentation
- Arguments
- Examples
- Source
- References
- Usages

### Test Execution
Run:
- Current test
- Current suite
- Selected suites
- By tags
- Failed tests
- Entire project

Execution history should be stored.

### Reports
Built-in report viewer.

No browser.

Future integration with ReportLens.

### AI Assistant
Future feature.

Examples:
- Explain failure
- Generate keyword
- Improve Robot code
- Convert SeleniumLibrary to Browser Library
- Generate documentation

---

## Non Goals

Do NOT build:
- A replacement for VS Code
- Git client
- Docker integration
- Kubernetes integration
- General Python IDE
- C/C++ support

Stay focused on Robot Framework.

---

## Tech Stack

Frontend:
- Flutter Desktop

Backend:
- Python

Communication:
- Local REST API or IPC

Database:
- SQLite

Execution:
- Python subprocesses

Package management:
- pip

Virtual environments:
- Python venv module

---

## Architecture Requirements

Use clean architecture.

Suggested layers:

Presentation

Application

Domain

Infrastructure

Core

Everything should be modular.

Every feature should be implemented as a module.

Example:

workspace

project

environment

packages

execution

keywords

reports

settings

plugins

Each module should expose interfaces instead of depending directly on implementations.

Avoid God classes.

Avoid tight coupling.

Use dependency injection where appropriate.

---

## UI Requirements

Modern desktop UI.

Minimal.

Beautiful.

Fast.

Dark mode first.

Left sidebar:
- Explorer
- Tests
- Keywords
- Packages

Main area:
- Editor
- Reports
- Documentation

Bottom panel:
- Console
- Execution logs

Top toolbar:
- Run
- Stop
- Environment selector
- Package Manager
- AI

---

## Development Strategy

Do NOT generate the whole application immediately.

Instead:

1. Design the architecture.
2. Explain every module.
3. Design folder structure.
4. Design data models.
5. Design APIs.
6. Explain communication between frontend and backend.
7. Explain why each decision is made.
8. Point out potential scalability problems.
9. Suggest improvements.

Once the architecture is finalized, implement the application incrementally in small milestones.

Never skip directly to writing large amounts of code.

Always prioritize maintainability, extensibility, and clean design over speed.