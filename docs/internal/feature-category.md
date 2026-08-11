I actually agree with Cursor's critique.

You're at the dangerous stage of a product where every missing feature looks important. That's exactly how products become "VS Code, but worse."

The question you should ask for every feature is:

> **"Would this make someone intentionally open Robot Studio instead of Cursor?"**

If the answer is **no**, don't build it unless it's blocking.

---

# Category A — Install-worthy features (build these)

These are features that don't really exist anywhere in a polished RF-first experience.

### Robot Debugger

Pause before keyword, step over, inspect variables, continue.

### Execution Replay

Replay execution step-by-step from `output.xml`.

### Test Impact Analysis

"I changed this keyword. Which tests are affected?"

### Robot Doctor

Analyze project and report:

* missing libraries
* unused resources
* duplicate keywords
* dead variables
* circular imports
* broken paths
* slow suites

### Flaky Test Analyzer

History of failures.

Show:

```
Login Test

Passed
Passed
Failed
Passed
Failed
```

Probability of flakiness.

---

### Keyword Call Hierarchy

```
Login
 ├── Smoke.robot
 ├── Checkout.robot
 └── API.robot
```

and

```
Checkout
 ├── Login
 ├── Open Browser
 └── Verify
```

---

### Keyword Extraction

Highlight

```
Input Text
Click
Verify
```

↓

```
Create Keyword
```

---

### Rename Keyword safely

Rename across workspace.

---

### Safe Delete

Before deleting

```
Delete Keyword?

Referenced in:

Login.robot
Smoke.robot
Checkout.robot
```

---

### Robot Metrics

Per project

```
keywords
tests
libraries
resources
variables

average keyword length

duplicate keywords

dead keywords

orphan resources
```

---

### Timeline View

Visual execution

```
Open Browser
█████

Login
███████

Checkout
██████████

API
███
```

---

### Test Heatmap

Files with highest failures.

---

### Smart Test Selection

After edit

```
Run affected tests

27 tests
```

instead of

```
Run all 2400
```

---

# Category B — Daily productivity

These keep people coming back every day.

### Auto-import library

Use unknown keyword

↓

```
Import SeleniumLibrary?
```

---

### Auto-import resource

Unknown keyword

↓

```
Import keywords.robot?
```

---

### Generate keyword documentation

AI optional later.

---

### Generate keyword from steps

---

### Extract variables

Turn

```
https://...
```

into

```
${BASE_URL}
```

---

### Find duplicate keywords

---

### Dead keyword detection

---

### Dead variable detection

---

### Broken resource detection

---

### Missing library repair

---

### Resource dependency graph

---

### Test dependency graph

---

### Keyword complexity warnings

---

### Suite health score

---

# Category C — Run intelligence

Robot Framework is about execution. Own it.

### Failed keyword explorer

```
Run

Login

↓

Keyword

↓

line

↓

variables

↓

screenshots

↓

logs
```

---

### Retry from failed keyword

Instead of rerunning whole suite.

---

### Compare two executions

```
Yesterday vs Today
```

---

### Execution diff

```
Keyword time

+120ms

-1 failure

+2 retries
```

---

### Performance regression detection

---

### Execution trend charts

---

### Failure clustering

Group similar failures automatically.

---

# Category D — Project intelligence

### Workspace health dashboard

---

### Environment health

---

### Library compatibility checker

---

### Robot version migration assistant

---

### Dependency updater

---

### Project analyzer

---

# Category E — AI (only after the above)

AI should use Robot Studio's unique context, not be a generic chat box.

### Explain failure using:

* output.xml
* log.html
* report.html
* stack traces
* variables
* execution history

---

### Suggest fix

---

### Generate Robot tests

---

### Generate keywords

---

### Explain keyword

---

### Convert Selenium to Browser

---

### Refactor Robot project

---

### Detect flaky root cause

---

# Things I would NOT build

These consume huge effort and won't make people switch:

* Generic Git Graph
* Built-in CI dashboard
* Markdown editor
* Database browser
* SSH client
* Docker UI
* Terminal emulator
* JSON/YAML editor
* Generic AI chat
* Minimap clones
* Generic extension marketplace
* Theme marketplace
* Hex editor
* Image viewer
* Generic diff tools

Users already have excellent tools for these.

---

## If I had to pick only **10 features** to build over the next year, I'd choose:

1. Robot Debugger
2. Robot Doctor
3. Test Impact Analysis
4. Execution Replay
5. Flaky Test Analyzer
6. Safe Rename + Safe Delete (workspace-aware refactoring)
7. Auto-import Library/Resource
8. Keyword Call Hierarchy + Dependency Graph
9. Compare Runs + Execution Timeline
10. AI Failure Analysis grounded in Robot Studio's execution data

Those ten features reinforce each other around the core workflow of **writing, understanding, running, debugging, and maintaining Robot Framework projects**. That's a much stronger product direction than trying to match every feature in VS Code or Cursor.
