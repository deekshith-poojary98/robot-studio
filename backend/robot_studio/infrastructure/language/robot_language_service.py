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

from robot_studio.infrastructure.language.builtin_keywords import BUILTIN_KEYWORDS

_BUILTIN_KEYWORDS = BUILTIN_KEYWORDS
_SETTING_NAMES = [
    "Library",
    "Resource",
    "Variables",
    "Documentation",
    "Suite Setup",
    "Suite Teardown",
    "Test Setup",
    "Test Teardown",
    "Test Timeout",
    "Force Tags",
    "Default Tags",
    "Metadata",
]


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
        kind = self._kind_for_context(context)
        results = await self.store.search_symbols(prefix, kind=kind, limit=80)

        items: list[dict] = []
        seen: set[str] = set()

        def add(label: str, item_kind: str, detail: str = "", insert: str | None = None) -> None:
            key = f"{item_kind}:{label.lower()}"
            if key in seen:
                return
            seen.add(key)
            items.append(
                {
                    "label": label,
                    "kind": item_kind,
                    "detail": detail,
                    "documentation": "",
                    "insert_text": insert or label,
                },
            )

        if context in {"setting", "library", "resource"}:
            for name in _SETTING_NAMES:
                if not prefix or name.lower().startswith(prefix.lower()):
                    add(name, "setting")
        if context in {"library", "keyword_call", "keyword"}:
            for name in _BUILTIN_KEYWORDS:
                if not prefix or prefix.lower() in name.lower():
                    add(name, "keyword", detail="BuiltIn")
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
        if symbol is None:
            return None
        return {
            "name": symbol["name"],
            "kind": symbol["kind"],
            "file_path": symbol["file_path"],
            "line": symbol["line"],
            "documentation": symbol.get("documentation") or "",
            "detail": symbol.get("detail") or "",
            "id": symbol["id"],
        }

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
    def _imported_libraries(content: str) -> list[str]:
        libraries: list[str] = []
        for raw in content.splitlines():
            line = raw.strip()
            if line.lower().startswith("library "):
                token = line.split(None, 1)[1].strip().split("    ")[0].strip()
                if token:
                    libraries.append(token)
        return libraries

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
        known_resources = {
            item["name"].casefold()
            for item in await self.store.search_symbols("", kind=SymbolKind.RESOURCE, limit=200)
        }
        known_libraries = {
            item["name"].casefold()
            for item in await self.store.search_symbols("", kind=SymbolKind.LIBRARY, limit=200)
        }
        declared_variables: set[str] = set()

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
            var_match = re.match(r"^(\$\{[^}]+\}|@\{[^}]+\}|&\{[^}]+\})", line)
            if var_match:
                declared_variables.add(var_match.group(1))
                continue
            if line.lower().startswith("resource "):
                token = line.split(None, 1)[1].strip().split("    ")[0]
                if (
                    token.casefold() not in known_resources
                    and Path(token).stem.casefold() not in known_resources
                ):
                    diagnostics.append(
                        self._diag(
                            file_path,
                            idx,
                            f"Missing resource '{token}'",
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
                if keyword.startswith("[") and keyword.endswith("]"):
                    continue
                if (
                    keyword
                    and not keyword.startswith("$")
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
                for var_token in re.findall(r"\$\{[^}]+\}|@\{[^}]+\}|&\{[^}]+\}", raw):
                    if var_token not in declared_variables:
                        definition = await self.store.find_definition(
                            var_token,
                            kind=SymbolKind.VARIABLE,
                        )
                        if definition is None:
                            diagnostics.append(
                                self._diag(
                                    file_path,
                                    idx,
                                    f"Unknown variable '{var_token}'",
                                    "information",
                                ),
                            )

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

