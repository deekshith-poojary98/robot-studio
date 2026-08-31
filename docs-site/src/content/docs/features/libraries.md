---
title: Libraries
description: Browse Robot Framework libraries, keywords, docs, and arguments from the side rail.
---

Open **Libraries** from the activity bar, **View → Libraries**, or the command palette (**Show Libraries**).

With a project open you can:

- Browse **BuiltIn** plus libraries named in a `Library` setting in any `.robot` or `.resource` file (including `__init__.robot`)
- Open a library to see its keywords
- Read documentation and argument details
- Jump to source when a definition location is known

Python files, resource files, and variable files are **not** listed on their own. Add `Library    ExcelSage.py` (or the library name) in Settings for that library to appear — the same import the tests use. Libraries that fail to load in the [active environment](/workflows/environments/) stay off the list.

Libraries is for **browsing keyword APIs**. Installing packages belongs on the **Packages** rail — see [Environments & packages](/workflows/environments/).
