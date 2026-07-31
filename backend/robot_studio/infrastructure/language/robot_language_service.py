"""Index + Robot parsing backed Language Service implementation."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import EventBus, EnvironmentActivated, IndexUpdated
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.interfaces.language import LanguageService
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.robot_parsing_bridge import (
    RobotParsingBridge,
    RobotParsingError,
)

from robot_studio.infrastructure.language.builtin_keywords import (
    AUTOMATIC_VARIABLE_NAMES,
    BUILTIN_KEYWORDS,
    CONTINUATION_MARKER,
    CONTROL_MARKERS,
    CONTROL_STRUCTURES,
    LOCAL_SETTINGS,
    SECTION_HEADERS,
    SETTING_NAMES,
)

_BUILTIN_KEYWORDS = BUILTIN_KEYWORDS
_SETTING_NAMES = SETTING_NAMES
_LOCAL_SETTINGS = LOCAL_SETTINGS
_CONTROL_STRUCTURES = CONTROL_STRUCTURES
_CONTROL_MARKERS = CONTROL_MARKERS
_SECTION_HEADERS = SECTION_HEADERS
_AUTOMATIC_VARIABLE_NAMES = AUTOMATIC_VARIABLE_NAMES
_CONTINUATION_MARKER = CONTINUATION_MARKER


@dataclass
class RobotLanguageService(LanguageService):
    store: SqliteIndexStore
    context: WorkspaceContext
    parsing: RobotParsingBridge = field(default_factory=RobotParsingBridge)
    event_bus: EventBus | None = None
    _cache_generation: int = field(default=0, init=False)
    _subscribed: bool = field(default=False, init=False)
    _library_cache: dict[str, dict[str, Any]] = field(default_factory=dict, init=False)

    def start(self) -> None:
        if self._subscribed or self.event_bus is None:
            return
        self.event_bus.subscribe(IndexUpdated, self._on_index_updated)
        self.event_bus.subscribe(EnvironmentActivated, self._on_environment_activated)
        self._subscribed = True

    async def _on_index_updated(self, event: IndexUpdated) -> None:
        _ = event
        self._cache_generation += 1

    async def _on_environment_activated(self, event: EnvironmentActivated) -> None:
        _ = event
        self._library_cache.clear()
        self._cache_generation += 1

    def _python_executable(self) -> Path:
        environment = self.context.environment
        if environment is None:
            raise RobotParsingError(
                "Activate a Python environment before using language features",
            )
        return self.parsing.resolve_python(environment.path)

    async def completion(self, request: dict) -> list[dict]:
        file_path = str(request.get("file_path") or "")
        line = int(request.get("line") or 1)
        column = int(request.get("column") or 1)
        content = str(request.get("content") or "")
        query = str(request.get("query") or request.get("prefix") or "")

        ctx: dict[str, Any] = {"prefix": query, "context": "keyword"}
        if content and file_path:
            try:
                ctx = await self.parsing.run(
                    self._python_executable(),
                    op="completion_context",
                    content=content,
                    file_path=file_path,
                    line=line,
                    column=column,
                )
            except RobotParsingError:
                pass

        prefix = str(ctx.get("prefix") or query).strip()
        context = str(ctx.get("context") or "keyword")
        section = str(ctx.get("section") or "")
        kind = self._kind_for_context(context)
        results = await self.store.search_symbols(prefix, kind=kind, limit=80)

        items: list[dict] = []
        seen: set[str] = set()

        def add(
            label: str,
            item_kind: str,
            detail: str = "",
            insert: str | None = None,
            documentation: str = "",
        ) -> None:
            key = f"{item_kind}:{label.lower()}"
            if key in seen:
                return
            seen.add(key)
            items.append(
                {
                    "label": label,
                    "kind": item_kind,
                    "detail": detail,
                    "documentation": documentation,
                    "insert_text": insert or label,
                },
            )

        def matches(label: str) -> bool:
            """Prefix / word-start match — not substring (``a`` must not hit ``RANGE``)."""
            if not prefix:
                return True
            needle = prefix.casefold()
            hay = label.casefold()
            if hay.startswith(needle):
                return True
            return any(
                part.startswith(needle)
                for part in re.split(r"[\s.]+", hay)
                if part
            )

        # Section headers when typing at column 0 with *** …
        if prefix.startswith("*") or context == "section":
            for header in _SECTION_HEADERS:
                if matches(header):
                    add(header, "section", detail="Section header")

        if context in {"setting", "library", "resource"} or section == "settings":
            for name in _SETTING_NAMES:
                if matches(name):
                    add(name, "setting", detail="Suite setting")

        if context == "local_setting" or prefix.startswith("["):
            for name in _LOCAL_SETTINGS:
                if matches(name):
                    add(name, "setting", detail="Local setting")

        if context in {"library", "keyword_call", "keyword", "control"}:
            for marker in _CONTROL_STRUCTURES:
                label = marker["label"]
                # Match the short DSL label only — insert templates contain
                # incidental letters (RANGE, ${a}, …) that must not match.
                if matches(label):
                    add(
                        label,
                        "dsl",
                        detail=marker.get("detail") or "RF DSL",
                        insert=marker.get("insert_text") or label,
                        documentation=marker.get("documentation") or "",
                    )
            # Avoid flooding the dropdown with every BuiltIn when the prefix is empty.
            builtin_source = _BUILTIN_KEYWORDS
            if len(prefix) < 1:
                builtin_source = [
                    "Log",
                    "Log To Console",
                    "Should Be Equal",
                    "Should Be True",
                    "Set Variable",
                    "Create List",
                    "Create Dictionary",
                    "Fail",
                    "Sleep",
                    "No Operation",
                    "Run Keyword",
                    "Evaluate",
                    "Get Length",
                    "Get Variable Value",
                    "Wait Until Keyword Succeeds",
                ]
            for name in builtin_source:
                if matches(name):
                    add(
                        name,
                        "keyword",
                        detail="BuiltIn library",
                        documentation="BuiltIn library keyword (not RF DSL).",
                    )
            # Prefer live BuiltIn names from the active env when available.
            if len(prefix) >= 1:
                try:
                    resolved = await self._resolve_library("BuiltIn")
                    if resolved.get("available"):
                        for name in resolved.get("keywords") or []:
                            if matches(str(name)):
                                add(
                                    str(name),
                                    "keyword",
                                    detail="BuiltIn library",
                                    documentation="BuiltIn library keyword (not RF DSL).",
                                )
                except Exception:  # noqa: BLE001 — completion must stay resilient
                    pass

            # Keywords from Library imports in this file (active env via libdoc).
            if content and len(prefix) >= 1:
                try:
                    for lib_name, alias in self._imported_library_entries(content):
                        if lib_name.casefold() == "builtin":
                            continue
                        resolved = await self._resolve_library(lib_name)
                        if not resolved.get("available"):
                            continue
                        display = str(resolved.get("name") or lib_name)
                        for kw in resolved.get("keywords") or []:
                            kw_name = str(kw)
                            if alias:
                                qualified = f"{alias}.{kw_name}"
                                if matches(qualified) or matches(kw_name):
                                    add(
                                        qualified,
                                        "keyword",
                                        detail=f"{display} (as {alias})",
                                        documentation=str(
                                            ((resolved.get("keyword_info") or {}).get(
                                                kw_name.casefold(),
                                            )
                                            or {}).get("documentation")
                                            or "",
                                        ),
                                    )
                            elif matches(kw_name):
                                add(
                                    kw_name,
                                    "keyword",
                                    detail=f"{display} library",
                                    documentation=str(
                                        ((resolved.get("keyword_info") or {}).get(
                                            kw_name.casefold(),
                                        )
                                        or {}).get("documentation")
                                        or "",
                                    ),
                                )
                except Exception:  # noqa: BLE001 — completion must stay resilient
                    pass

        for item in results:
            add(
                item["name"],
                item["kind"],
                detail=item.get("detail") or "",
            )
            if len(items) >= 100:
                break
        return items[:100]

    async def hover(self, request: dict) -> dict | None:
        symbol = await self._resolve(request)
        if symbol is not None:
            return {
                "name": symbol["name"],
                "kind": symbol["kind"],
                "file_path": symbol["file_path"],
                "line": symbol["line"],
                "documentation": symbol.get("documentation") or "",
                "detail": symbol.get("detail") or "",
                "id": symbol["id"],
            }

        # Env / library keywords are not in the workspace index.
        name = str(request.get("name") or request.get("symbol") or "").strip()
        content = str(request.get("content") or "")
        file_path = str(request.get("file_path") or "")
        line = int(request.get("line") or 1)
        if not name and content:
            try:
                ctx = await self.parsing.run(
                    self._python_executable(),
                    op="completion_context",
                    content=content,
                    file_path=file_path,
                    line=line,
                    column=int(request.get("column") or 1),
                )
                name = str(ctx.get("prefix") or "").strip()
            except RobotParsingError:
                name = ""
        if not name:
            return None

        env_info = await self._lookup_keyword_signature(content or "", name)
        if env_info is not None:
            parameters = list(env_info.get("parameters") or [])
            detail = ", ".join(
                str(item.get("label") or "")
                for item in parameters
                if item.get("label")
            )
            return {
                "name": str(env_info.get("name") or name),
                "kind": SymbolKind.KEYWORD.value,
                "file_path": file_path,
                "line": line,
                "documentation": str(env_info.get("documentation") or ""),
                "detail": detail,
                "id": "",
            }

        for library_name in self._imported_libraries(content):
            if library_name.casefold() != name.casefold():
                continue
            resolved = await self._resolve_library(library_name)
            if not resolved.get("available"):
                continue
            return {
                "name": str(resolved.get("name") or library_name),
                "kind": SymbolKind.LIBRARY.value,
                "file_path": file_path,
                "line": line,
                "documentation": f"Library available in the active environment "
                f"({len(resolved.get('keywords') or [])} keywords).",
                "detail": str(resolved.get("name") or library_name),
                "id": "",
            }
        return None

    async def diagnostics(self, request: dict) -> list[dict]:
        file_path = str(request.get("file_path") or "")
        content = str(request.get("content") or "")
        if not content:
            return []

        diagnostics: list[dict] = []
        try:
            parsed = await self.parsing.run(
                self._python_executable(),
                op="diagnostics",
                content=content,
                file_path=file_path,
            )
            for item in parsed:
                diagnostics.append(
                    {
                        "severity": item.get("severity") or "error",
                        "file_path": file_path,
                        "line": int(item.get("line") or 1),
                        "column": int(item.get("column") or 1),
                        "message": str(item.get("message") or ""),
                        "source": item.get("source") or "robot",
                    },
                )
        except RobotParsingError as exc:
            diagnostics.append(
                {
                    "severity": "warning",
                    "file_path": file_path,
                    "line": 1,
                    "column": 1,
                    "message": str(exc),
                    "source": "robot.parser",
                },
            )

        await self._append_semantic_diagnostics(content, file_path, diagnostics)
        return diagnostics

    async def definition(self, request: dict) -> dict | None:
        symbol = await self._resolve(request)
        if symbol is None:
            return None
        return {
            "id": symbol["id"],
            "name": symbol["name"],
            "kind": symbol["kind"],
            "file_path": symbol["file_path"],
            "line": symbol["line"],
            "documentation": symbol.get("documentation") or "",
            "detail": symbol.get("detail") or "",
        }

    async def references(self, request: dict) -> list[dict]:
        symbol = await self._resolve(request)
        if symbol is None:
            return []
        refs = await self.store.find_references(symbol["id"])
        if not refs:
            refs = await self.store.find_references(symbol["name"])
        return refs

    async def format_document(self, request: dict) -> str:
        content = str(request.get("content") or "")
        file_path = str(request.get("file_path") or "")
        start_line = request.get("start_line")
        end_line = request.get("end_line")
        if not content:
            return content
        if start_line is not None and end_line is not None:
            return await self._format_selection(
                content,
                int(start_line),
                int(end_line),
                file_path,
            )
        suffix = Path(file_path).suffix.lower()
        if suffix not in {".robot", ".resource"}:
            return self._basic_format(content)
        try:
            return await self.parsing.run(
                self._python_executable(),
                op="format",
                content=content,
                file_path=file_path,
            )
        except RobotParsingError:
            return self._basic_format(content)

    async def signature_help(self, request: dict) -> dict | None:
        file_path = str(request.get("file_path") or "")
        line = int(request.get("line") or 1)
        column = int(request.get("column") or 1)
        content = str(request.get("content") or "")
        if not content:
            return None

        parsed: dict[str, Any] | None = None
        try:
            parsed = await self.parsing.run(
                self._python_executable(),
                op="signature_help",
                content=content,
                file_path=file_path,
                line=line,
                column=column,
            )
        except RobotParsingError:
            return None
        if not parsed:
            return None

        keyword = str(parsed.get("keyword") or "")
        if not keyword:
            return None
        definition = await self.store.find_definition(keyword, kind=SymbolKind.KEYWORD)
        documentation = ""
        detail = ""
        parameters: list[dict] = []
        if definition:
            documentation = definition.get("documentation") or ""
            detail = definition.get("detail") or ""
            parameters = self._parameters_from_detail(detail)
        if not parameters and keyword in _BUILTIN_KEYWORDS:
            parameters = [{"label": "message", "documentation": ""}]

        # Library keywords live in the active env, not the workspace index.
        if not parameters or not documentation:
            env_info = await self._lookup_keyword_signature(content, keyword)
            if env_info is not None:
                if not parameters:
                    parameters = list(env_info.get("parameters") or [])
                if not documentation:
                    documentation = str(env_info.get("documentation") or "")
                if not detail and parameters:
                    detail = ", ".join(
                        str(item.get("label") or "")
                        for item in parameters
                        if item.get("label")
                    )

        if not parameters and not documentation:
            return None

        active = int(parsed.get("active_parameter") or 0)
        if parameters:
            active = max(0, min(active, len(parameters) - 1))
        return {
            "keyword": keyword,
            "documentation": documentation,
            "detail": detail,
            "active_parameter": active,
            "parameters": parameters,
        }

    async def _lookup_keyword_signature(
        self,
        content: str,
        keyword: str,
    ) -> dict[str, Any] | None:
        key = keyword.casefold()
        for library_name in [*self._imported_libraries(content), "BuiltIn"]:
            resolved = await self._resolve_library(library_name)
            if not resolved.get("available"):
                continue
            info = (resolved.get("keyword_info") or {}).get(key)
            if isinstance(info, dict):
                return info
        return None

    @staticmethod
    def _imported_library_entries(content: str) -> list[tuple[str, str | None]]:
        """Parse ``Library`` settings → ``(name, WITH NAME alias | None)``."""
        entries: list[tuple[str, str | None]] = []
        for raw in content.splitlines():
            line = raw.strip()
            if not line.lower().startswith("library "):
                continue
            rest = line.split(None, 1)[1].strip()
            cells = [cell for cell in re.split(r"[ \t]{2,}|\t+", rest) if cell]
            if not cells:
                # Single-space fallback: first token is the library name.
                tokens = rest.split()
                if not tokens:
                    continue
                entries.append((tokens[0], None))
                continue
            lib_name = cells[0].strip()
            alias: str | None = None
            for index, cell in enumerate(cells):
                if cell.upper() == "WITH NAME" and index + 1 < len(cells):
                    alias = cells[index + 1].strip() or None
                    break
            if lib_name:
                entries.append((lib_name, alias))
        return entries

    @staticmethod
    def _imported_libraries(content: str) -> list[str]:
        return [name for name, _alias in RobotLanguageService._imported_library_entries(content)]

    async def _resolve(self, request: dict) -> dict | None:
        symbol_id = request.get("symbol_id")
        if symbol_id:
            return await self.store.get_symbol(str(symbol_id))
        name = request.get("name") or request.get("symbol") or request.get("query")
        if not name:
            file_path = request.get("file_path")
            line = request.get("line")
            column = request.get("column")
            content = request.get("content")
            if content and file_path and line:
                try:
                    ctx = await self.parsing.run(
                        self._python_executable(),
                        op="completion_context",
                        content=str(content),
                        file_path=str(file_path),
                        line=int(line),
                        column=int(column or 1),
                    )
                    name = ctx.get("prefix")
                except RobotParsingError:
                    name = None
        if not name:
            return None
        kind_raw = request.get("kind")
        kind = None
        if kind_raw:
            try:
                kind = SymbolKind(str(kind_raw))
            except ValueError:
                kind = None
        return await self.store.find_definition(str(name), kind=kind)

    async def _append_semantic_diagnostics(
        self,
        content: str,
        file_path: str,
        diagnostics: list[dict],
    ) -> None:
        lines = content.splitlines()
        known_keywords = {
            item["name"].casefold()
            for item in await self.store.search_symbols("", kind=SymbolKind.KEYWORD, limit=500)
        }
        known_keywords.update(name.casefold() for name in _BUILTIN_KEYWORDS)
        known_keywords.update(name.casefold() for name in _CONTROL_MARKERS)
        known_keywords.update(name.casefold() for name in _LOCAL_SETTINGS)
        known_keywords.update(name.casefold() for name in self._collect_local_keyword_names(lines))
        known_libraries = {
            item["name"].casefold()
            for item in await self.store.search_symbols("", kind=SymbolKind.LIBRARY, limit=200)
        }
        declared_variables = self._collect_declared_variables(lines)

        # Resolve Library imports against the active env (site-packages), not only
        # the workspace index — Environments/ is excluded from discovery.
        imported_libraries = self._imported_libraries(content)

        for library_name in imported_libraries:
            resolved = await self._resolve_library(library_name)
            if resolved.get("available"):
                known_libraries.add(library_name.casefold())
                known_libraries.add(str(resolved.get("name") or library_name).casefold())
                for keyword in resolved.get("keywords") or []:
                    known_keywords.add(str(keyword).casefold())

        for idx, raw in enumerate(lines, start=1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # Continuation rows (`...    arg`) are RF syntax, not keyword calls.
            if line.startswith(_CONTINUATION_MARKER):
                continue
            if line.lower().startswith("resource "):
                token = line.split(None, 1)[1].strip().split("    ")[0]
                if not self._import_path_exists(file_path, token):
                    diagnostics.append(
                        self._diag(
                            file_path,
                            idx,
                            f"Missing resource '{token}'",
                            "warning",
                        ),
                    )
                continue
            if line.lower().startswith("variables "):
                token = line.split(None, 1)[1].strip().split("    ")[0]
                if not self._import_path_exists(file_path, token):
                    diagnostics.append(
                        self._diag(
                            file_path,
                            idx,
                            f"Missing variables file '{token}'",
                            "warning",
                        ),
                    )
                continue
            if line.lower().startswith("library "):
                token = line.split(None, 1)[1].strip().split("    ")[0].strip()
                if token.casefold() not in known_libraries:
                    diagnostics.append(
                        self._diag(
                            file_path,
                            idx,
                            f"Missing library '{token}'",
                            "warning",
                        ),
                    )
                continue
            if raw.startswith(" ") or raw.startswith("\t"):
                keyword = self._keyword_cell(raw)
                if keyword == _CONTINUATION_MARKER:
                    continue
                if keyword.startswith("[") and keyword.endswith("]"):
                    # Still scan argument variables on local-setting rows.
                    pass
                elif (
                    keyword
                    and not keyword.startswith("$")
                    and not keyword.startswith("@")
                    and not keyword.startswith("&")
                    and keyword.casefold() not in known_keywords
                ):
                    diagnostics.append(
                        self._diag(
                            file_path,
                            idx,
                            f"Unknown keyword '{keyword}'",
                            "warning",
                        ),
                    )
                for var_token in re.findall(r"\$\{[^}]+\}|@\{[^}]+\}|&\{[^}]+\}|%\{[^}]+\}", raw):
                    normalized = self._normalize_variable_token(var_token)
                    if self._is_known_variable(normalized, declared_variables):
                        continue
                    definition = await self.store.find_definition(
                        normalized,
                        kind=SymbolKind.VARIABLE,
                    )
                    if definition is None:
                        diagnostics.append(
                            self._diag(
                                file_path,
                                idx,
                                f"Unknown variable '{normalized}'",
                                "information",
                            ),
                        )

    @staticmethod
    def _path_beside_file(file_path: str, relative: str) -> Path:
        base = Path(file_path).expanduser().resolve().parent
        return (base / relative).resolve()

    @classmethod
    def _import_path_exists(cls, file_path: str, token: str) -> bool:
        """True when a Resource/Variables import resolves to a real file on disk.

        Do **not** trust the symbol index here: ResourceImport lines are indexed as
        ``kind=resource`` even when the target file is missing, which previously
        suppressed ``Missing resource`` warnings.
        """
        cleaned = token.strip().strip("'\"")
        if not cleaned:
            return False
        candidate = Path(cleaned).expanduser()
        if candidate.is_file():
            return True
        return cls._path_beside_file(file_path, cleaned).is_file()

    @classmethod
    def _collect_local_keyword_names(cls, lines: list[str]) -> set[str]:
        """User-keyword names declared in this file's Keywords section."""
        names: set[str] = set()
        in_keywords = False
        for raw in lines:
            stripped = raw.strip()
            if stripped.startswith("*") and stripped.endswith("*"):
                label = stripped.strip("*").strip().casefold()
                in_keywords = label in {"keywords", "keyword"}
                continue
            if not in_keywords or not stripped or stripped.startswith("#"):
                continue
            if raw.startswith(" ") or raw.startswith("\t"):
                continue
            if stripped.startswith("["):
                continue
            names.add(stripped)
        return names

    @classmethod
    def _collect_declared_variables(cls, lines: list[str]) -> set[str]:
        declared: set[str] = set()
        for raw in lines:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            cells = cls._robot_cells(line)
            if not cells:
                continue
            head = cells[0]
            head_upper = head.upper()

            if head.casefold() == "[arguments]":
                for cell in cells[1:]:
                    match = re.match(r"([\$@&%]\{[^}]+\})", cell)
                    if match:
                        declared.add(match.group(1))
                continue

            if head_upper == "VAR" and len(cells) > 1:
                match = re.match(r"^([\$@&%]\{[^}]+\})$", cells[1])
                if match:
                    declared.add(match.group(1))
                continue

            if head_upper == "FOR":
                for cell in cells[1:]:
                    if cell.upper() in {
                        "IN",
                        "IN RANGE",
                        "IN ENUMERATE",
                        "IN ZIP",
                    }:
                        break
                    match = re.match(r"^([\$@&%]\{[^}]+\})$", cell)
                    if match:
                        declared.add(match.group(1))
                continue

            # ${x}=    Keyword   /   ${x}    value   /   ${x}=value-in-one-cell
            assign = re.match(r"^([\$@&%]\{[^}]+\})\s*=?\s*$", head)
            if assign:
                declared.add(assign.group(1))
                continue
            assign_inline = re.match(r"^([\$@&%]\{[^}]+\})=", head)
            if assign_inline:
                declared.add(assign_inline.group(1))
        return declared

    @staticmethod
    def _robot_cells(line: str) -> list[str]:
        return [cell for cell in re.split(r"[ \t]{2,}|\t+", line.strip()) if cell]

    @staticmethod
    def _normalize_variable_token(token: str) -> str:
        cleaned = token.strip()
        if cleaned.endswith("="):
            cleaned = cleaned[:-1]
        return cleaned

    @classmethod
    def _is_known_variable(cls, token: str, declared: set[str]) -> bool:
        normalized = cls._normalize_variable_token(token)
        if normalized in declared:
            return True
        match = re.match(r"^([\$@&%])\{(.+)\}$", normalized)
        if not match:
            return False
        sigil, name = match.group(1), match.group(2)
        if sigil == "%":
            return True  # %{ENV} — environment variables
        folded = name.casefold()
        if folded in _AUTOMATIC_VARIABLE_NAMES:
            return True
        # Number variables: ${10}, ${3.14}, ${0xFF}, ${1_000}, …
        if sigil == "$" and cls._is_number_variable_name(name):
            return True
        upper = name.upper()
        if upper.startswith(("TEST_", "SUITE_", "PREV_TEST_", "KEYWORD_")):
            return True
        return False

    @staticmethod
    def _is_number_variable_name(name: str) -> bool:
        """True when RF would accept the body of ``${…}`` as a number literal."""
        cleaned = name.strip().replace("_", "")
        if not cleaned:
            return False
        try:
            int(cleaned, 0)
            return True
        except ValueError:
            pass
        try:
            float(cleaned)
            return True
        except ValueError:
            return False

    async def _resolve_library(self, name: str) -> dict[str, Any]:
        cleaned = name.strip()
        if not cleaned:
            return {"available": False, "keywords": []}
        try:
            python = self._python_executable()
        except RobotParsingError:
            return {"available": False, "keywords": []}
        cache_key = f"{python}::{cleaned.casefold()}"
        cached = self._library_cache.get(cache_key)
        if cached is not None:
            return cached
        try:
            result = await self.parsing.run(
                python,
                op="resolve_library",
                library=cleaned,
            )
            if not isinstance(result, dict):
                result = {"available": False, "keywords": []}
        except RobotParsingError:
            result = {"available": False, "keywords": []}
        self._library_cache[cache_key] = result
        return result

    @staticmethod
    def _keyword_cell(raw: str) -> str:
        """Return the keyword cell from an indented Robot row (supports multi-word)."""
        cells = [cell for cell in re.split(r"[ \t]{2,}|\t+", raw.strip()) if cell]
        if not cells:
            return ""
        if re.match(r"^[\$@&%]", cells[0]) and len(cells) > 1:
            return cells[1].strip()
        return cells[0].strip()

    @staticmethod
    def _diag(file_path: str, line: int, message: str, severity: str) -> dict:
        return {
            "severity": severity,
            "file_path": file_path,
            "line": line,
            "column": 1,
            "message": message,
            "source": "robot.semantic",
        }

    @staticmethod
    def _kind_for_context(context: str) -> SymbolKind | None:
        mapping = {
            "library": SymbolKind.LIBRARY,
            "resource": SymbolKind.RESOURCE,
            "variable": SymbolKind.VARIABLE,
            "keyword": SymbolKind.KEYWORD,
            "keyword_call": SymbolKind.KEYWORD,
            "setting": SymbolKind.SETTING,
            "local_setting": SymbolKind.SETTING,
            "section": SymbolKind.SETTING,
            "control": SymbolKind.KEYWORD,
        }
        return mapping.get(context)

    @staticmethod
    def _parameters_from_detail(detail: str) -> list[dict]:
        if not detail:
            return []
        args = [part.strip() for part in detail.split(",") if part.strip()]
        params: list[dict] = []
        for arg in args:
            label = arg
            doc = ""
            if "=" in arg:
                label, default = arg.split("=", 1)
                label = label.strip()
                doc = f"default: {default.strip()}"
            params.append({"label": label, "documentation": doc})
        return params

    async def _format_selection(
        self,
        content: str,
        start_line: int,
        end_line: int,
        file_path: str,
    ) -> str:
        lines = content.splitlines()
        if start_line < 1:
            start_line = 1
        if end_line > len(lines):
            end_line = len(lines)
        if start_line > end_line or not lines:
            return content
        selected = "\n".join(lines[start_line - 1 : end_line])
        suffix = Path(file_path).suffix.lower()
        if suffix in {".robot", ".resource"}:
            try:
                formatted = await self.parsing.run(
                    self._python_executable(),
                    op="format",
                    content=selected,
                    file_path=file_path,
                )
            except RobotParsingError:
                formatted = self._basic_format(selected)
        else:
            formatted = self._basic_format(selected)
        merged = (
            lines[: start_line - 1]
            + formatted.splitlines()
            + lines[end_line:]
        )
        trailing_newline = content.endswith("\n")
        result = "\n".join(merged)
        return result + ("\n" if trailing_newline else "")

    @staticmethod
    def _basic_format(content: str) -> str:
        lines = [line.rstrip() for line in content.splitlines()]
        while lines and not lines[-1].strip():
            lines.pop()
        return "\n".join(lines) + ("\n" if lines else "")

