If your goal is to make people **leave VS Code/Cursor** for Robot Studio, don't chase generic IDE features. You'll lose. They already have 10+ years of polish.

Instead, build features that make people say:

> "I wish VS Code had this for Robot Framework."

Here's the list I'd prioritize.

---

# Environment & Project

* One-click project bootstrap
* Python interpreter switcher
* Environment health checker
* Missing dependency detector
* Requirements sync
* Robot Framework version manager
* Python package conflict detector
* Environment snapshot/export

---

# Test Authoring

* Keyword parameter hints
* Smart keyword completion
* Auto-import missing library/resource
* Extract keywords refactoring
* Rename keyword across workspace
* Rename variable across workspace
* Duplicate test detection
* Unused keyword detector
* Unused variable detector
* Dead resource detection
* Circular resource import detection
* Generate test from template
* AI-assisted keyword generation (later)

---

# Running Tests

* Run failed since last execution
* Run changed tests
* Run current folder
* Run by tags
* Run by selection
* Run with variables
* Run with custom arguments
* Run multiple configurations
* Parallel execution profiles
* Execution queue
* Cancel queued runs
* Scheduled test execution

---

# Debugging

* Robot Framework debugger
* Step over keyword
* Step into keyword
* Step out
* Breakpoints
* Conditional breakpoints
* Variable watch window
* Live variable inspector
* Call stack viewer
* Keyword execution timeline

*(Huge differentiator. VS Code barely has this.)*

---

# Reports

* Built-in report dashboard
* Historical trends
* Failure analytics
* Slowest keywords
* Slowest test cases
* Flaky test detector
* Compare two executions
* Screenshot gallery
* Log search
* Report annotations

---

# Test Explorer

* Live execution status
* Test duration badges
* Failed test badges
* Last execution result
* Last execution time
* Retry failed directly
* Favorite tests
* Test collections
* Smart filtering

---

# Robot Framework Intelligence

* Keyword usage graph
* Resource dependency graph
* Variable references
* Library dependency viewer
* Keyword call hierarchy
* Workspace symbol explorer
* Robot syntax visualizer
* Missing documentation warnings
* Auto documentation preview

---

# Editor

* Multi-cursor editing
* Column selection
* Code folding
* Breadcrumb navigation
* Sticky section headers
* Minimap
* Inline errors
* Inline quick fixes
* Rainbow variables
* Code snippets
* Live templates
* Surround with TRY/IF/FOR
* Drag & drop keyword reordering

---

# Refactoring

* Move keyword to resource
* Move tests between files
* Split robot file
* Merge robot files
* Convert duplicated steps into keyword
* Organize imports
* Sort variables
* Remove unused imports

---

# Git

* Commit from failed tests
* Blame current keyword
* Git timeline for robot file
* Diff report between commits
* Run tests changed in commit
* PR review mode
* Git graph

---

# CI/CD

* Jenkins integration
* GitHub Actions integration
* Azure DevOps integration
* Trigger pipeline
* Watch pipeline
* Download artifacts
* Compare local vs CI failures

---

# Robot Framework Libraries

* Library documentation browser
* Keyword search across installed libraries
* Install library from IDE
* Update libraries
* Library compatibility checker
* Generate Libdoc automatically
* **Resource documentation browser (later)** — Libraries docs stays for `Library` imports (BuiltIn, pip packages, custom `.py`). Resource files (`.resource` / shared `.robot` keyword files via `Resource`) are a different RF concept; consider a sibling “Resources” panel or a combined keyword-sources browser with separate Libraries / Resources sections. Parked after Libraries-docs polish (2026-08-09).

---

# Package Manager

* Recommended libraries
* Popular libraries
* Latest updates
* Security advisories
* Changelog viewer

---

# File Explorer

* New file/folder
* Duplicate file
* Move file
* Refactor folders
* Reveal in OS
* Favorite folders
* Recent files
* Workspace bookmarks

---

# AI (later)

* Explain keyword
* Explain failure
* Generate keyword
* Generate tests
* Fix Robot syntax
* Convert Selenium → Browser
* Generate documentation
* Chat with execution logs
* Flaky test analysis

---

# Robot Studio Exclusive Ideas (These can become your USP)

These are the ones I think could genuinely make people install Robot Studio:

* Live Keyword Flow Visualizer
* Interactive Execution Timeline
* Keyword Performance Profiler
* Resource Dependency Graph
* Variable Flow Inspector
* One-click Project Health Report
* Robot Framework Doctor (finds common project issues)
* Test Impact Analysis (run only tests affected by changed keywords/resources)
* Flaky Test Analyzer
* Smart Tag Suggestions
* Test Smell Detector
* Auto-generate Page Object/Keyword skeletons
* Execution Replay (step through a completed run)
* Robot Metrics Dashboard
* Workspace Architecture Viewer

## My top 10 priorities

If I were building Robot Studio, I'd do these next:

1. Robot Framework Debugger
2. Test Impact Analysis
3. Flaky Test Detection
4. Project Health Dashboard
5. Extract/Rename Refactoring
6. Interactive Execution Timeline
7. Robot Framework Doctor
8. Library Documentation Browser
9. AI Failure Analysis
10. CI/CD Integration

The common thread is that none of these are "another text editor feature." They're features built around how Robot Framework projects are actually developed and maintained. That's where Robot Studio has the best chance of becoming something people open because it solves Robot Framework problems better than a general-purpose IDE.
