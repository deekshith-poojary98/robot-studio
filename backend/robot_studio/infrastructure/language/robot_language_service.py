"""Index + Robot parsing backed Language Service implementation."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import EventBus, IndexUpdated
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.interfaces.language import LanguageService
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.robot_parsing_bridge import (
    RobotParsingBridge,
    RobotParsingError,
)

_BUILTIN_KEYWORDS = [
    "Log",
    "Should Be Equal",
    "Should Contain",
    "Fail",
    "Pass Execution",
    "Run Keyword",
    "Run Keywords",
    "Wait Until Keyword Succeeds",
]
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

    def start(self) -> None:
        if self._subscribed or self.event_bus is None:
            return
        self.event_bus.subscribe(IndexUpdated, self._on_index_updated)
        self._subscribed = True

    async def _on_index_updated(self, event: IndexUpdated) -> None:
        _ = event
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

        active = int(parsed.get("active_parameter") or 0)
        return {
            "keyword": keyword,
            "documentation": documentation,
            "detail": detail,
            "active_parameter": active,
            "parameters": parameters,
        }

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
            item["name"].lower()
            for item in await self.store.search_symbols("", kind=SymbolKind.KEYWORD, limit=500)
        }
        known_keywords.update(name.lower() for name in _BUILTIN_KEYWORDS)
        known_resources = {
            item["name"].lower()
            for item in await self.store.search_symbols("", kind=SymbolKind.RESOURCE, limit=200)
        }
        known_libraries = {
            item["name"].lower()
            for item in await self.store.search_symbols("", kind=SymbolKind.LIBRARY, limit=200)
        }
        declared_variables: set[str] = set()
        imported_resources: set[str] = set()
        imported_libraries: set[str] = set()

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
                imported_resources.add(Path(token).stem.lower())
                if token.lower() not in known_resources and Path(token).stem.lower() not in known_resources:
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
                token = line.split(None, 1)[1].strip().split("    ")[0]
                imported_libraries.add(token.lower())
                if token.lower() not in known_libraries:
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
                token = raw.strip().split()[0] if raw.strip() else ""
                if token and not token.startswith("$") and token.lower() not in known_keywords:
                    diagnostics.append(
                        self._diag(
                            file_path,
                            idx,
                            f"Unknown keyword '{token}'",
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

