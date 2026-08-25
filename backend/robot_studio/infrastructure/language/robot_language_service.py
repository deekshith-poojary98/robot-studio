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
from robot_studio.domain.models.analysis import EntityKind
from robot_studio.infrastructure.analysis.engine import RobotAnalysisEngine
from robot_studio.infrastructure.analysis.normalize import (
    normalize_keyword_name,
    strip_bdd_prefix,
    strip_library_prefix,
)
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
from robot_studio.domain.interfaces.completion import CompletionRequestContext
from robot_studio.domain.interfaces.signature_help import SignatureHelpRequestContext
from robot_studio.infrastructure.language.completion import (
    BufferCompletionProvider,
    CompletionPipeline,
    DslCompletionProvider,
    FilesCompletionProvider,
    IndexSymbolCompletionProvider,
    KeywordCompletionProvider,
    NamedArgumentCompletionProvider,
    SectionCompletionProvider,
    SettingCompletionProvider,
    SqliteCompletionUsageStore,
    VariableCompletionProvider,
    resolve_keyword_via_pipeline,
)
from robot_studio.infrastructure.language.completion.python_provider import (
    PythonBufferCompletionProvider,
    PythonIndexCompletionProvider,
)
from robot_studio.infrastructure.language.python_language import (
    python_completion_context,
    python_signature_help,
)
from robot_studio.infrastructure.language.keyword_helpers import (
    active_parameter_index,
    parameters_from_detail_string,
)
from robot_studio.infrastructure.language.document_analysis import DocumentAnalysisService
from robot_studio.infrastructure.language.library_catalog import LibraryCatalogService
from robot_studio.domain.models.keyword_metadata import KeywordMetadata
from robot_studio.domain.models.library_metadata import LibraryMetadata
from robot_studio.infrastructure.language.signature import (
    IndexSignatureHelpProvider,
    LibdocSignatureHelpProvider,
    SignatureHelpPipeline,
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
    analysis_engine: RobotAnalysisEngine | None = None
    usage_store: SqliteCompletionUsageStore | None = None
    _cache_generation: int = field(default=0, init=False)
    _subscribed: bool = field(default=False, init=False)
    _completion_pipeline: CompletionPipeline | None = field(default=None, init=False)
    _signature_pipeline: SignatureHelpPipeline | None = field(default=None, init=False)
    _library_catalog: LibraryCatalogService | None = field(default=None, init=False)
    _document_analysis: DocumentAnalysisService | None = field(default=None, init=False)

    def start(self) -> None:
        if self._subscribed or self.event_bus is None:
            return
        self.event_bus.subscribe(IndexUpdated, self._on_index_updated)
        self.event_bus.subscribe(EnvironmentActivated, self._on_environment_activated)
        self._subscribed = True

    async def _on_index_updated(self, event: IndexUpdated) -> None:
        _ = event
        self._cache_generation += 1
        # Imports / index generation changed — drop catalog membership + resolved libs.
        if self._library_catalog is not None:
            self._library_catalog.invalidate()
        if self._document_analysis is not None:
            self._document_analysis.invalidate()
        self._signature_pipeline = None
        self._completion_pipeline = None

    async def _on_environment_activated(self, event: EnvironmentActivated) -> None:
        _ = event
        self._cache_generation += 1
        if self._library_catalog is not None:
            self._library_catalog.invalidate()
        if self._document_analysis is not None:
            self._document_analysis.invalidate()
        self._signature_pipeline = None
        self._completion_pipeline = None

    def _python_executable(self) -> Path:
        environment = self.context.environment
        if environment is None:
            raise RobotParsingError(
                "Activate a Python environment before using language features",
            )
        return self.parsing.resolve_python(environment.path)

    def library_catalog(self) -> LibraryCatalogService:
        """Canonical semantic cache — sole resolve_library owner."""
        if self._library_catalog is not None:
            return self._library_catalog

        async def discover_imports() -> list[str]:
            return await self._discover_library_imports()

        async def resolve_raw(name: str) -> dict[str, Any]:
            return await self._resolve_library_raw(name)

        self._library_catalog = LibraryCatalogService(
            _resolve_raw=resolve_raw,
            _discover_imports=discover_imports,
        )
        return self._library_catalog

    async def _discover_library_imports(self) -> list[tuple[str, str]]:
        """Library docs membership: resolvable Library imports + project ``.py`` libs.

        Returns ``(import_name, importing_file)`` so relative path libraries can be
        resolved against the suite that imported them.

        Resource files (``.robot`` / ``.resource``) are intentionally excluded —
        they are not test libraries; browse them in Explorer / Outline instead.
        """
        entries: list[tuple[str, str]] = []
        seen: set[str] = set()
        workspace = self.context.workspace
        try:
            symbols = await self.store.search_symbols(
                "",
                kind=SymbolKind.LIBRARY,
                workspace_id=workspace.id if workspace is not None else None,
                limit=200,
            )
        except Exception:  # noqa: BLE001
            symbols = []
        for item in symbols:
            name = str(item.get("name") or "").strip()
            if not name:
                continue
            source = str(item.get("file_path") or "")
            detail = str(item.get("detail") or "").casefold()

            # Resource files are not libraries — keep them out of Library docs.
            if self._is_resource_path(name):
                continue

            if self._looks_like_library_path(name):
                # Prefer absolute path when the suite path is known; still pass
                # the suite as file_path so libdoc can fall back.
                target = self._library_resolve_target(name, source)
                key = target.casefold()
                if key in seen:
                    continue
                seen.add(key)
                entries.append((target, source))
            elif (
                detail == "python"
                or (
                    source.lower().endswith(".py")
                    and Path(source).is_file()
                    and Path(source).stem.casefold() == name.casefold()
                )
            ):
                target = str(Path(source).expanduser().resolve())
                if self._is_resource_path(target):
                    continue
                key = target.casefold()
                if key in seen:
                    continue
                seen.add(key)
                entries.append((target, source))
            else:
                key = name.casefold()
                if key in seen:
                    continue
                seen.add(key)
                entries.append((name, source))
        return entries

    @staticmethod
    def _is_resource_path(token: str) -> bool:
        lower = token.strip().strip("'\"").lower().replace("\\", "/")
        return lower.endswith((".robot", ".resource"))

    def document_analysis(self) -> DocumentAnalysisService:
        """Canonical owner of buffer → DocumentSymbolTree (Outline / fold / crumbs)."""
        if self._document_analysis is not None:
            return self._document_analysis

        async def run_tree(content: str, file_path: str) -> dict:
            try:
                python = self._python_executable()
            except RobotParsingError:
                from robot_studio.infrastructure.language.robot_parsing_worker import (
                    document_symbol_tree,
                )

                return document_symbol_tree(content, file_path)
            try:
                result = await self.parsing.run(
                    python,
                    op="document_symbol_tree",
                    content=content,
                    file_path=file_path,
                )
                return result if isinstance(result, dict) else {}
            except RobotParsingError:
                from robot_studio.infrastructure.language.robot_parsing_worker import (
                    document_symbol_tree,
                )

                return document_symbol_tree(content, file_path)

        self._document_analysis = DocumentAnalysisService(_run_tree=run_tree)
        return self._document_analysis

    async def analyze_document(self, file_path: str, content: str) -> dict:
        tree = await self.document_analysis().analyze(file_path, content)
        return tree.to_api()

    async def list_libraries(self, *, extra_imports: list[str] | None = None) -> list[dict]:
        libs = await self.library_catalog().list_libraries(extra_imports=extra_imports)
        return [lib.to_summary_api() for lib in libs]

    async def get_library(self, name: str) -> dict | None:
        lib = await self.library_catalog().get_library(name)
        if lib is None:
            return None
        return lib.to_api()

    def _ensure_signature_pipeline(self) -> SignatureHelpPipeline:
        if self._signature_pipeline is not None:
            return self._signature_pipeline

        async def find_definition(
            name: str,
            *,
            kind: SymbolKind | None = None,
        ) -> dict | None:
            return await self.store.find_definition(name, kind=kind)

        catalog = self.library_catalog()
        self._signature_pipeline = SignatureHelpPipeline(
            providers=[
                LibdocSignatureHelpProvider(
                    catalog=catalog,
                    imported_libraries=self._imported_libraries,
                ),
                IndexSignatureHelpProvider(find_definition=find_definition),
            ],
        )
        return self._signature_pipeline

    def _ensure_completion_pipeline(self) -> CompletionPipeline:
        if self._completion_pipeline is not None:
            return self._completion_pipeline

        async def search_symbols(
            prefix: str,
            *,
            kind: SymbolKind | None = None,
            limit: int = 80,
        ) -> list[dict]:
            workspace = self.context.workspace
            return await self.store.search_symbols(
                prefix,
                kind=kind,
                limit=limit,
                workspace_id=workspace.id if workspace is not None else None,
            )

        signature_pipeline = self._ensure_signature_pipeline()
        catalog = self.library_catalog()
        self._completion_pipeline = CompletionPipeline(
            providers=[
                PythonBufferCompletionProvider(),
                PythonIndexCompletionProvider(search_symbols=search_symbols),
                NamedArgumentCompletionProvider(
                    resolve_keyword=resolve_keyword_via_pipeline(signature_pipeline),
                ),
                SectionCompletionProvider(),
                SettingCompletionProvider(),
                DslCompletionProvider(),
                BufferCompletionProvider(),
                VariableCompletionProvider(search_symbols=search_symbols),
                KeywordCompletionProvider(
                    catalog=catalog,
                    imported_library_entries=self._imported_library_entries_transitive,
                    search_symbols=search_symbols,
                ),
                IndexSymbolCompletionProvider(search_symbols=search_symbols),
                FilesCompletionProvider(search_symbols=search_symbols),
            ],
            usage_store=self.usage_store,
        )
        return self._completion_pipeline

    async def record_completion_usage(
        self,
        *,
        label: str,
        kind: str = "",
        project_id: str | None = None,
    ) -> None:
        if self.usage_store is None:
            return
        pid = project_id
        if not pid and self.context.project is not None:
            pid = str(self.context.project.id)
        if not pid:
            return
        await self.usage_store.record(project_id=pid, label=label, kind=kind)

    async def completion(self, request: dict) -> list[dict]:
        file_path = str(request.get("file_path") or "")
        line = int(request.get("line") or 1)
        column = int(request.get("column") or 1)
        content = str(request.get("content") or "")
        query = str(request.get("query") or request.get("prefix") or "")

        is_python = file_path.lower().endswith(".py")
        ctx_raw: dict[str, Any] = {"prefix": query, "context": "keyword", "section": ""}
        if is_python and content:
            ctx_raw = python_completion_context(content, line, column)
        elif content and file_path:
            try:
                ctx_raw = await self.parsing.run(
                    self._python_executable(),
                    op="completion_context",
                    content=content,
                    file_path=file_path,
                    line=line,
                    column=column,
                )
            except RobotParsingError:
                pass

        prefix = str(ctx_raw.get("prefix") or query).strip()
        context = str(ctx_raw.get("context") or ("python" if is_python else "keyword"))
        section = str(ctx_raw.get("section") or "")
        keyword = str(ctx_raw.get("keyword") or "")
        arguments = tuple(str(a) for a in (ctx_raw.get("arguments") or []))
        active_parameter = int(ctx_raw.get("active_parameter") or 0)
        current_argument = str(ctx_raw.get("current_argument") or "")
        attribute_base = str(ctx_raw.get("attribute_base") or "")
        project_id = None
        if self.context.project is not None:
            project_id = str(self.context.project.id)

        request_ctx = CompletionRequestContext(
            file_path=file_path,
            content=content,
            line=line,
            column=column,
            prefix=prefix,
            context=context,
            section=section,
            project_id=project_id,
            keyword=keyword,
            arguments=arguments,
            active_parameter=active_parameter,
            current_argument=current_argument,
            attribute_base=attribute_base,
        )
        ranked = await self._ensure_completion_pipeline().complete(
            request_ctx,
            limit=100,
        )
        return [item.to_api() for item in ranked]

    async def hover(self, request: dict) -> dict | None:
        symbol = await self._resolve(request)
        content = str(request.get("content") or "")
        file_path = str(request.get("file_path") or "")
        if symbol is not None:
            detail = str(symbol.get("detail") or "")
            documentation = str(symbol.get("documentation") or "")
            # Open-buffer keywords may be newer than the last index pass —
            # prefer live [Arguments] / [Documentation] when available.
            if content and str(symbol.get("kind") or "") == SymbolKind.KEYWORD.value:
                live = await self._live_keyword_fields(
                    content,
                    file_path,
                    str(symbol.get("name") or ""),
                )
                if live is not None:
                    detail = str(live.get("detail") or detail)
                    documentation = str(live.get("documentation") or documentation)
            return {
                "name": symbol["name"],
                "kind": symbol["kind"],
                "file_path": symbol["file_path"],
                "line": symbol["line"],
                "documentation": documentation,
                "detail": detail,
                "id": symbol["id"],
            }

        # Env / library keywords are not in the workspace index.
        name = str(request.get("name") or request.get("symbol") or "").strip()
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

        for library_name in self._imported_libraries(content, file_path):
            if library_name.casefold() != name.casefold():
                continue
            resolved = await self.library_catalog().get_library(library_name)
            if resolved is None:
                continue
            return {
                "name": resolved.name or library_name,
                "kind": SymbolKind.LIBRARY.value,
                "file_path": file_path,
                "line": line,
                "documentation": resolved.documentation
                or (
                    f"Library available in the active environment "
                    f"({resolved.keyword_count} keywords)."
                ),
                "detail": resolved.name or library_name,
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
        await self._append_analysis_diagnostics(content, file_path, diagnostics)
        return diagnostics

    async def definition(self, request: dict) -> dict | None:
        symbols = await self._resolve_all(request)
        if not symbols:
            return None
        primary = self._symbol_payload(symbols[0])
        if len(symbols) > 1:
            primary["definitions"] = [self._symbol_payload(item) for item in symbols]
        return primary

    @staticmethod
    def _symbol_payload(symbol: dict) -> dict:
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

        if file_path.lower().endswith(".py"):
            return python_signature_help(content, line, column)

        parsed: dict[str, Any] | None = None
        try:
            parsed = await self.parsing.run(
                self._python_executable(),
                op="signature_help",
                content=content,
                file_path=file_path,
                line=line,
                column=column,
                hover=bool(request.get("hover")),
            )
        except RobotParsingError:
            return None
        if not parsed:
            return None

        keyword = str(parsed.get("keyword") or "")
        if not keyword:
            return None
        arguments = tuple(str(a) for a in (parsed.get("arguments") or []))
        if "arguments_completed" in parsed:
            completed = [str(a) for a in (parsed.get("arguments_completed") or [])]
        else:
            completed = list(arguments)
        hint = int(parsed.get("active_parameter") or 0)
        current_argument = str(parsed.get("current_argument") or "")

        ctx = SignatureHelpRequestContext(
            file_path=file_path,
            content=content,
            line=line,
            column=column,
            keyword=keyword,
            arguments=arguments,
            active_parameter_hint=hint,
            project_id=(
                str(self.context.project.id) if self.context.project is not None else None
            ),
        )
        meta = await self._ensure_signature_pipeline().resolve(ctx)
        if meta is None:
            return None
        # Prefer live [Arguments]/[Documentation] from the open buffer when the
        # index still has an empty detail (common for custom keywords).
        if content and (not meta.parameters or not meta.documentation):
            live = await self._live_keyword_fields(content, file_path, meta.name)
            if live is not None:
                live_detail = str(live.get("detail") or "")
                live_docs = str(live.get("documentation") or "")
                live_params = (
                    parameters_from_detail_string(live_detail)
                    if live_detail
                    else meta.parameters
                )
                if live_params or live_docs:
                    meta = KeywordMetadata(
                        name=meta.name,
                        qualified_name=meta.qualified_name,
                        source_type=meta.source_type,
                        library_name=meta.library_name,
                        documentation=live_docs or meta.documentation,
                        doc_format=meta.doc_format,
                        parameters=live_params or meta.parameters,
                        source_path=meta.source_path,
                        source_line=meta.source_line,
                        deprecated=meta.deprecated,
                        tags=meta.tags,
                        examples=meta.examples,
                        detail=live_detail or meta.detail,
                    )
        if not meta.parameters and not meta.documentation:
            return None

        active = active_parameter_index(
            meta,
            arguments=completed,
            active_hint=hint,
            typing_prefix=current_argument,
        )
        return meta.to_signature_api(active_parameter=active)

    async def _lookup_keyword_signature(
        self,
        content: str,
        keyword: str,
    ) -> dict[str, Any] | None:
        """Legacy helper — returns transport dict from KeywordMetadata for hover."""
        meta = await self._ensure_signature_pipeline().resolve(
            SignatureHelpRequestContext(
                file_path="",
                content=content,
                line=1,
                column=1,
                keyword=keyword,
            ),
        )
        if meta is None:
            return None
        return meta.to_transport()

    @staticmethod
    def _imported_library_entries(content: str) -> list[tuple[str, str | None]]:
        """Parse ``Library`` settings → ``(name, AS / WITH NAME alias | None)``."""
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
                marker = cell.upper()
                # RF accepts both modern ``AS`` and legacy ``WITH NAME``.
                if marker in {"AS", "WITH NAME"} and index + 1 < len(cells):
                    alias = cells[index + 1].strip() or None
                    break
            if lib_name:
                entries.append((lib_name, alias))
        return entries

    @staticmethod
    def _imported_resource_paths(content: str) -> list[str]:
        """Parse ``Resource`` settings → import path tokens."""
        paths: list[str] = []
        for raw in content.splitlines():
            line = raw.strip()
            if not line.lower().startswith("resource "):
                continue
            rest = line.split(None, 1)[1].strip()
            cells = [cell for cell in re.split(r"[ \t]{2,}|\t+", rest) if cell]
            token = (cells[0] if cells else rest.split()[0] if rest.split() else "").strip(
                "'\"",
            )
            if token and "${" not in token:
                paths.append(token)
        return paths

    @classmethod
    def _imported_library_entries_transitive(
        cls,
        content: str,
        file_path: str = "",
        *,
        max_depth: int = 8,
    ) -> list[tuple[str, str | None]]:
        """Libraries from this file plus resources it imports (RF transitive rule).

        Robot makes libraries imported by a resource available to every file
        that imports that resource. Diagnostics / completion must follow the
        same chain or ``Dictionary Should Contain Key`` looks "unknown" in
        endpoint resources that only ``Resource`` an api_client with Collections.
        """
        ordered: list[tuple[str, str | None]] = []
        seen_libs: set[str] = set()
        visited_files: set[str] = set()

        def _add_entries(entries: list[tuple[str, str | None]]) -> None:
            for name, alias in entries:
                key = f"{name.casefold()}::{(alias or '').casefold()}"
                if key in seen_libs:
                    continue
                seen_libs.add(key)
                ordered.append((name, alias))

        def _walk(text: str, path: str, depth: int) -> None:
            _add_entries(cls._imported_library_entries(text))
            if depth >= max_depth or not path:
                return
            try:
                resolved_here = str(Path(path).expanduser().resolve())
            except OSError:
                resolved_here = path
            if resolved_here in visited_files:
                return
            visited_files.add(resolved_here)
            for token in cls._imported_resource_paths(text):
                candidate = Path(token).expanduser()
                if not candidate.is_file():
                    candidate = cls._path_beside_file(path, token)
                if not candidate.is_file():
                    continue
                try:
                    child = candidate.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                _walk(child, str(candidate), depth + 1)

        _walk(content, file_path, 0)
        return ordered

    @classmethod
    def _imported_libraries(cls, content: str, file_path: str = "") -> list[str]:
        return [
            name
            for name, _alias in cls._imported_library_entries_transitive(
                content,
                file_path,
            )
        ]

    async def _resolve(self, request: dict) -> dict | None:
        symbols = await self._resolve_all(request)
        return symbols[0] if symbols else None

    async def _resolve_all(self, request: dict) -> list[dict]:
        symbol_id = request.get("symbol_id")
        if symbol_id:
            symbol = await self.store.get_symbol(str(symbol_id))
            return [symbol] if symbol else []

        name = request.get("name") or request.get("symbol") or request.get("query")
        file_path = request.get("file_path")
        line = request.get("line")
        column = request.get("column")
        content = request.get("content")

        # Prefer RF cell under cursor when content is available.
        if content and line:
            cell = self._robot_cell_at(str(content), int(line), int(column or 1))
            if cell:
                name = cell
            if not name:
                try:
                    ctx = await self.parsing.run(
                        self._python_executable(),
                        op="completion_context",
                        content=str(content),
                        file_path=str(file_path or ""),
                        line=int(line),
                        column=int(column or 1),
                    )
                    name = ctx.get("prefix") or ctx.get("keyword") or name
                except RobotParsingError:
                    pass

        if not name:
            return []

        kind_raw = request.get("kind")
        kind = None
        if kind_raw:
            try:
                kind = SymbolKind(str(kind_raw))
            except ValueError:
                kind = None

        symbols = await self.store.find_definitions(str(name), kind=kind, limit=20)
        if symbols:
            return symbols

        # Analysis Engine fallback — semantic graph keyword entities.
        analysis_hits = await self._definitions_from_analysis(str(name))
        return analysis_hits

    async def _live_keyword_fields(
        self,
        content: str,
        file_path: str,
        name: str,
    ) -> dict | None:
        """Parse open-buffer keywords for up-to-date args / docs."""
        cleaned = (name or "").strip()
        if not cleaned or not content.strip():
            return None
        try:
            symbols = await self.parsing.run(
                self._python_executable(),
                op="document_symbols",
                content=content,
                file_path=file_path or "buffer.robot",
            )
        except RobotParsingError:
            return None
        needle = cleaned.casefold()
        for item in symbols if isinstance(symbols, list) else []:
            if not isinstance(item, dict):
                continue
            if str(item.get("kind") or "") != SymbolKind.KEYWORD.value:
                continue
            if str(item.get("name") or "").casefold() != needle:
                continue
            return {
                "detail": str(item.get("detail") or ""),
                "documentation": str(item.get("documentation") or ""),
            }
        return None

    @staticmethod
    def _robot_cell_at(content: str, line: int, column: int) -> str | None:
        lines = content.splitlines()
        if line < 1 or line > len(lines):
            return None
        raw = lines[line - 1]
        if not raw.strip() or raw.lstrip().startswith("#"):
            return None
        # Split Robot cells on 2+ spaces or tabs, preserving 1-based columns.
        cells: list[tuple[int, int, str]] = []
        parts = re.split(r"(\t+|[ ]{2,})", raw)
        pos = 1
        for part in parts:
            if not part:
                continue
            if re.fullmatch(r"\t+|[ ]{2,}", part):
                pos += len(part)
                continue
            leading = len(part) - len(part.lstrip(" "))
            token = part.strip()
            start = pos + leading
            end = start + max(len(token) - 1, 0)
            if token:
                cells.append((start, end, token))
            pos += len(part)
        for start, end, token in cells:
            if start <= column <= max(end, start):
                if token.startswith("...") or token.startswith("["):
                    return None
                return token
        # Column past last cell → last keyword-ish cell.
        for _start, _end, token in reversed(cells):
            if token and not token.startswith("#"):
                return token
        return None

    async def _definitions_from_analysis(self, name: str) -> list[dict]:
        if self.analysis_engine is None:
            return []
        project = self.context.project
        if project is None:
            return []
        try:
            matches = await self.analysis_engine.store.find_entities_by_normalized_name(
                normalize_keyword_name(name),
                project_id=project.id,
                kinds=[
                    EntityKind.KEYWORD.value,
                    EntityKind.VARIABLE.value,
                    EntityKind.TEST_CASE.value,
                ],
            )
        except Exception:  # noqa: BLE001
            return []
        out: list[dict] = []
        for entity in matches:
            out.append(
                {
                    "id": str(entity.id),
                    "name": entity.name,
                    "kind": entity.kind.value,
                    "file_path": str(entity.file_path),
                    "line": entity.line,
                    "documentation": entity.documentation or "",
                    "detail": entity.detail or "analysis",
                },
            )
        return out

    async def _append_analysis_diagnostics(
        self,
        content: str,
        file_path: str,
        diagnostics: list[dict],
    ) -> None:
        """Merge Analysis Engine missing-import findings into Problems."""
        if self.analysis_engine is None:
            return
        project = self.context.project
        if project is None:
            return
        try:
            missing = await self.analysis_engine.find_missing_imports(project.id)
        except Exception:  # noqa: BLE001
            return
        target = str(Path(file_path).expanduser().resolve()) if file_path else ""
        existing = {
            (d.get("line"), str(d.get("message") or "").casefold())
            for d in diagnostics
        }
        for edge in missing:
            source_file = str(Path(edge.source_file).resolve()) if edge.source_file else ""
            if target and source_file and source_file != target:
                continue
            name = edge.target_name or "unknown"
            kind = edge.edge_kind or ""
            if kind.endswith("variables"):
                message = f"Unresolved variables import '{name}'"
            else:
                message = f"Unresolved import '{name}'"
            line = int(edge.source_line or 1)
            key = (line, message.casefold())
            if key in existing:
                continue
            # Unify with an existing semantic Missing resource/import diagnostic —
            # share Doctor inspection identity instead of duplicating or dropping.
            matched = False
            for diagnostic in diagnostics:
                if int(diagnostic.get("line") or 0) != line:
                    continue
                text = str(diagnostic.get("message") or "").casefold()
                if name.casefold() not in text:
                    continue
                if "missing" not in text and "unresolved" not in text and "import" not in text:
                    continue
                diagnostic["code"] = "missing_import"
                diagnostic["inspection_id"] = "missing_import"
                if diagnostic.get("source") in {None, "robot", "robot.semantic", "robot.parser"}:
                    diagnostic["source"] = "analysis"
                    diagnostic["message"] = message
                matched = True
                break
            if matched:
                existing.add(key)
                continue
            diagnostics.append(
                {
                    **self._diag(file_path or source_file, line, message, "warning"),
                    "source": "analysis",
                    "code": "missing_import",
                    "inspection_id": "missing_import",
                },
            )
            existing.add(key)

    async def _append_semantic_diagnostics(
        self,
        content: str,
        file_path: str,
        diagnostics: list[dict],
    ) -> None:
        lines = content.splitlines()
        workspace = self.context.workspace
        known_keywords = {
            item["name"].casefold()
            for item in await self.store.search_symbols(
                "",
                kind=SymbolKind.KEYWORD,
                limit=500,
                workspace_id=workspace.id if workspace is not None else None,
            )
        }
        known_keywords.update(name.casefold() for name in _BUILTIN_KEYWORDS)
        known_keywords.update(name.casefold() for name in _CONTROL_MARKERS)
        known_keywords.update(name.casefold() for name in _LOCAL_SETTINGS)
        known_keywords.update(name.casefold() for name in self._collect_local_keyword_names(lines))
        declared_variables = self._collect_declared_variables(lines, file_path=file_path)

        # Resolve Library imports against the active env only. Do not seed
        # "known" libraries from the workspace index — the indexer records
        # Library *import* names as LIBRARY symbols even when unresolved, which
        # made Missing library warnings disappear right after save/reindex.
        imported_libraries = self._imported_libraries(content, file_path)
        resolved_libraries: set[str] = set()

        for library_name in imported_libraries:
            target = self._library_resolve_target(library_name, file_path)
            resolved = await self.library_catalog().get_library(target)
            if resolved is None and target != library_name:
                resolved = await self.library_catalog().get_library(library_name)
            if resolved is None:
                # Path-like imports are relative to the suite file (Robot's rule).
                # Treat an on-disk target as present even when libdoc fails.
                if self._looks_like_library_path(library_name) and self._import_path_exists(
                    file_path,
                    library_name,
                ):
                    resolved_libraries.add(library_name.casefold())
                    resolved_libraries.add(target.casefold())
                continue
            resolved_libraries.add(library_name.casefold())
            resolved_libraries.add(target.casefold())
            resolved_libraries.add(resolved.name.casefold())
            for keyword in resolved.keywords:
                known_keywords.add(keyword.name.casefold())

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
                if token.casefold() not in resolved_libraries:
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
                    and not self._is_known_keyword_call(keyword, known_keywords)
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

    @staticmethod
    def _looks_like_library_path(token: str) -> bool:
        """True for path-style Library imports (``.py`` / relative / absolute)."""
        cleaned = token.strip().strip("'\"")
        if not cleaned:
            return False
        lower = cleaned.lower().replace("\\", "/")
        if lower.endswith((".py", ".robot", ".resource")):
            return True
        return "/" in lower or cleaned.startswith(".")

    @classmethod
    def _library_resolve_target(cls, name: str, file_path: str) -> str:
        """Map a Library import to an absolute path when it is path-like."""
        cleaned = name.strip().strip("'\"")
        if not cls._looks_like_library_path(cleaned):
            return cleaned
        candidate = Path(cleaned).expanduser()
        if candidate.is_file():
            return str(candidate.resolve())
        if file_path:
            beside = cls._path_beside_file(file_path, cleaned)
            if beside.is_file():
                return str(beside)
        return cleaned

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
    def _collect_declared_variables(
        cls,
        lines: list[str],
        *,
        file_path: str = "",
    ) -> set[str]:
        declared: set[str] = set()
        for raw in lines:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue

            if line.lower().startswith("variables ") and file_path:
                token = line.split(None, 1)[1].strip().split("    ")[0].strip().strip("'\"")
                declared.update(cls._variables_from_import_file(file_path, token))

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
            # Multi-assign: ${a}    ${b}=    Keyword
            consumed_assign = False
            for cell in cells:
                bare = cell[:-1].rstrip() if cell.endswith("=") else cell
                match = re.match(r"^([\$@&%]\{[^}]+\})$", bare)
                if match:
                    declared.add(match.group(1))
                    consumed_assign = True
                    if cell.endswith("="):
                        break
                    continue
                break
            if consumed_assign:
                continue
        return declared

    @classmethod
    def _variables_from_import_file(cls, file_path: str, token: str) -> set[str]:
        """Names exported by a Robot ``Variables`` import (``.py`` / YAML)."""
        if not token or "${" in token:
            return set()
        candidate = Path(token).expanduser()
        if not candidate.is_file():
            candidate = cls._path_beside_file(file_path, token)
        if not candidate.is_file():
            return set()
        suffix = candidate.suffix.lower()
        if suffix == ".py":
            return cls._variables_from_python_file(candidate)
        if suffix in {".yaml", ".yml"}:
            return cls._variables_from_yaml_file(candidate)
        return set()

    @staticmethod
    def _variables_from_python_file(path: Path) -> set[str]:
        """Module-level assigns become ``${NAME}`` in Robot (Variables import)."""
        import ast

        try:
            tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
        except (OSError, SyntaxError):
            return set()
        names: set[str] = set()
        for node in tree.body:
            targets: list = []
            if isinstance(node, ast.Assign):
                targets.extend(node.targets)
            elif isinstance(node, ast.AnnAssign) and node.target is not None:
                targets.append(node.target)
            for target in targets:
                if isinstance(target, ast.Name) and not target.id.startswith("_"):
                    names.add(f"${{{target.id}}}")
        return names

    @staticmethod
    def _variables_from_yaml_file(path: Path) -> set[str]:
        names: set[str] = set()
        try:
            for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
                line = raw.strip()
                if not line or line.startswith("#") or ":" not in line:
                    continue
                key = line.split(":", 1)[0].strip()
                if key and not key.startswith("-") and re.match(
                    r"^[A-Za-z_][A-Za-z0-9_]*$",
                    key,
                ):
                    names.add(f"${{{key}}}")
        except OSError:
            return set()
        return names

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
        # Extended syntax: ${response.json()}, ${obj.attr}, ${list[0]}
        # — known when the base variable is declared.
        base = cls._extended_variable_base(name)
        names_to_match = {name}
        if base != name:
            names_to_match.add(base)
            if base.casefold() in _AUTOMATIC_VARIABLE_NAMES:
                return True
        # Robot allows ${list} vs @{list} for the same assignment.
        for item in declared:
            other = re.match(r"^([\$@&%])\{(.+)\}$", item)
            if other and other.group(2) in names_to_match:
                return True
        return False

    @staticmethod
    def _extended_variable_base(name: str) -> str:
        """Body of ``${…}`` with RF extended access (``.`` / ``[]``) stripped."""
        if RobotLanguageService._is_number_variable_name(name):
            return name
        cut = len(name)
        for marker in (".", "["):
            idx = name.find(marker)
            if 0 < idx < cut:
                cut = idx
        return name[:cut] if cut < len(name) else name

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

    async def _resolve_library_raw(
        self,
        name: str,
        file_path: str = "",
    ) -> dict[str, Any]:
        """Worker transport only — LibraryCatalogService is the sole caller/cache."""
        cleaned = name.strip()
        if not cleaned:
            return {"available": False, "keywords": []}
        # Absolutize path-style imports before the worker when we know the suite.
        if file_path and self._looks_like_library_path(cleaned):
            cleaned = self._library_resolve_target(cleaned, file_path)
        try:
            python = self._python_executable()
        except RobotParsingError:
            return {"available": False, "keywords": []}
        try:
            result = await self.parsing.run(
                python,
                op="resolve_library",
                library=cleaned,
                file_path=file_path,
            )
            if not isinstance(result, dict):
                result = {"available": False, "keywords": []}
        except RobotParsingError:
            result = {"available": False, "keywords": []}
        return result

    @staticmethod
    def _is_known_keyword_call(keyword: str, known_keywords: set[str]) -> bool:
        """True when *keyword* matches index/BuiltIn names, including BDD / Library. prefixes."""
        raw = keyword.strip()
        if not raw:
            return True
        candidates = {
            raw.casefold(),
            normalize_keyword_name(raw),
        }
        # BuiltIn.Log / SeleniumLibrary.Open Browser
        without_lib = strip_library_prefix(raw)
        if without_lib and without_lib != raw:
            candidates.add(without_lib.casefold())
            candidates.add(normalize_keyword_name(without_lib))
        # Given Login User → loginuser
        normalized = normalize_keyword_name(raw)
        stripped = strip_bdd_prefix(normalized)
        if stripped and stripped != normalized:
            candidates.add(stripped)
        # Given BuiltIn.Log → strip BDD then library
        without_bdd_raw = raw
        for prefix in ("Given ", "When ", "Then ", "And ", "But "):
            if without_bdd_raw.lower().startswith(prefix.lower()):
                without_bdd_raw = without_bdd_raw[len(prefix) :].lstrip()
                break
        if without_bdd_raw != raw:
            candidates.add(without_bdd_raw.casefold())
            candidates.add(normalize_keyword_name(without_bdd_raw))
            lib_free = strip_library_prefix(without_bdd_raw)
            if lib_free:
                candidates.add(lib_free.casefold())
                candidates.add(normalize_keyword_name(lib_free))
                candidates.add(strip_bdd_prefix(normalize_keyword_name(lib_free)))
        known_normalized = {normalize_keyword_name(name) for name in known_keywords}
        known_normalized.update(known_keywords)
        return any(item in known_normalized for item in candidates if item)

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

