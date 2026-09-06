"""Robot Analysis Engine — queryable semantic layer over the workspace graph."""

from __future__ import annotations

import asyncio
import json
import logging
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID

from robot_studio.core.events import AnalysisProgress, EventBus
from robot_studio.domain.interfaces.analysis import AnalysisEngine, AnalysisStore
from robot_studio.domain.models.analysis import (
    AnalysisSnapshot,
    BindingConfidence,
    DependencyNode,
    EdgeKind,
    EdgeRef,
    EntityKind,
    EntityRef,
    SemanticEntity,
    UsageStat,
)
from robot_studio.infrastructure.analysis.binder import (
    SemanticBinder,
    import_path_exists_on_disk,
)
from robot_studio.infrastructure.analysis.normalize import (
    keyword_lookup_keys,
    normalize_keyword_name,
    normalize_variable_name,
)
from robot_studio.infrastructure.analysis.semantic_extractor import (
    decode_call_context,
    extract_file_semantics,
    looks_like_keyword_literal,
    parse_keyword_arg_names,
    split_named_argument,
)
from robot_studio.infrastructure.analysis.sqlite_analysis_store import (
    SqliteAnalysisStore,
)

logger = logging.getLogger(__name__)

# Coalesce rapid single-file saves so a 10k-suite rebind does not run per keystroke.
_REBIND_DEBOUNCE_SECONDS = 0.75


def _entity_ref(entity: SemanticEntity) -> EntityRef:
    return EntityRef(
        id=entity.id,
        kind=entity.kind.value,
        name=entity.name,
        file_path=str(entity.file_path),
        line=entity.line,
        column=entity.column,
        documentation=entity.documentation,
        detail=entity.detail,
    )


@dataclass
class RobotAnalysisEngine(AnalysisEngine):
    store: AnalysisStore
    event_bus: EventBus | None = None
    binder: SemanticBinder = field(init=False)
    _rebind_tasks: dict[UUID, asyncio.Task] = field(default_factory=dict, init=False)

    def __post_init__(self) -> None:
        self.binder = SemanticBinder(self.store)

    async def ingest_file(
        self,
        path: Path,
        *,
        workspace_id: UUID | None,
        project_id: UUID | None,
        rebind: bool = True,
    ) -> None:
        """Incremental: replace one file's subgraph; optionally rebind the project."""
        if path.suffix.lower() not in {".robot", ".resource"}:
            return
        if project_id is None:
            return
        version = await self.store.get_graph_version(project_id)
        epoch = version.incremental_revision
        # robot.api parsing is sync/CPU — keep the API event loop free for Save.
        facts = await asyncio.to_thread(
            extract_file_semantics,
            path,
            workspace_id=workspace_id,
            project_id=project_id,
        )
        await self.store.replace_file_graph(
            path,
            facts.entities,
            facts.edges,
            epoch=epoch,
        )
        if rebind:
            await self.store.bump_revision(project_id, new_graph_version=False)
            self._schedule_rebind(project_id)

    async def finalize_project(self, project_id: UUID) -> AnalysisSnapshot:
        """Bump revision, rebind all edges, invalidate caches — call after bulk ingest."""
        await self._cancel_scheduled_rebind(project_id)
        await self.store.bump_revision(project_id, new_graph_version=False)
        await self.binder.rebind_project(project_id)
        return await self.snapshot(project_id)

    async def remove_file(
        self,
        path: Path,
        *,
        project_id: UUID | None,
        rebind: bool = True,
    ) -> None:
        await self.store.clear_file(path)
        if project_id:
            await self.store.bump_revision(project_id, new_graph_version=False)
            if rebind:
                self._schedule_rebind(project_id)

    def _schedule_rebind(self, project_id: UUID) -> None:
        existing = self._rebind_tasks.get(project_id)
        if existing is not None and not existing.done():
            existing.cancel()

        async def _run() -> None:
            try:
                await asyncio.sleep(_REBIND_DEBOUNCE_SECONDS)
                await self.binder.rebind_project(project_id)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Debounced analysis rebind failed for %s", project_id)
            finally:
                current = self._rebind_tasks.get(project_id)
                if current is not None and current.done():
                    self._rebind_tasks.pop(project_id, None)

        self._rebind_tasks[project_id] = asyncio.create_task(
            _run(),
            name=f"analysis-rebind-{project_id}",
        )

    async def _cancel_scheduled_rebind(self, project_id: UUID) -> None:
        task = self._rebind_tasks.pop(project_id, None)
        if task is None:
            return
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

    async def rebuild_project(
        self,
        project_id: UUID,
        *,
        workspace_id: UUID | None,
        roots: list[Path],
    ) -> AnalysisSnapshot:
        """Full project semantic rebuild (explicit only)."""
        await self._cancel_scheduled_rebind(project_id)
        await self.store.clear_project(project_id)
        version = await self.store.bump_revision(project_id, new_graph_version=True)
        epoch = version.incremental_revision
        robot_files: list[Path] = []
        for root in roots:
            if not root.exists():
                continue
            for path in sorted(root.rglob("*")):
                if not path.is_file():
                    continue
                if path.suffix.lower() not in {".robot", ".resource"}:
                    continue
                parts = {p.lower() for p in path.parts}
                if parts & {".venv", "venv", "node_modules", ".git", ".robotstudio"}:
                    continue
                robot_files.append(path)
        total = len(robot_files)
        if self.event_bus is not None:
            await self.event_bus.publish(
                AnalysisProgress(
                    message=f"Building analysis graph… 0/{total}",
                    current=0,
                    total=total,
                    scope="project",
                    scope_id=str(project_id),
                ),
            )
        for index, path in enumerate(robot_files):
            facts = await asyncio.to_thread(
                extract_file_semantics,
                path,
                workspace_id=workspace_id,
                project_id=project_id,
            )
            await self.store.replace_file_graph(
                path,
                facts.entities,
                facts.edges,
                epoch=epoch,
            )
            current = index + 1
            if self.event_bus is not None and (
                index == 0 or current == total or index % 25 == 0
            ):
                await self.event_bus.publish(
                    AnalysisProgress(
                        message=f"Building analysis graph… {current}/{total}",
                        current=current,
                        total=total,
                        scope="project",
                        scope_id=str(project_id),
                    ),
                )
        return await self.finalize_project(project_id)

    async def snapshot(self, project_id: UUID) -> AnalysisSnapshot:
        version = await self.store.get_graph_version(project_id)
        counts = {"entities": 0, "edges": 0, "unbound_calls": 0}
        if isinstance(self.store, SqliteAnalysisStore):
            counts = await self.store.counts(project_id)
        return AnalysisSnapshot(
            project_id=str(project_id),
            graph_version=version.graph_version,
            incremental_revision=version.incremental_revision,
            epoch=version.epoch,
            timestamp=version.timestamp,
            entity_count=counts["entities"],
            edge_count=counts["edges"],
            unbound_calls=counts["unbound_calls"],
        )

    async def _cached_models(
        self,
        project_id: UUID,
        key: str,
        builder,
        model_cls,
        *,
        nested: bool = False,
    ):
        cache_key = f"{project_id}:{key}"
        cached = await self.store.get_cache(cache_key)
        if cached is not None:
            data = json.loads(cached)
            if nested:
                return [[model_cls.model_validate(i) for i in group] for group in data]
            return [model_cls.model_validate(item) for item in data]
        value = await builder()
        epoch = await self.store.get_epoch(project_id)
        if nested:
            payload = [[i.model_dump(mode="json") for i in group] for group in value]
        else:
            payload = [item.model_dump(mode="json") for item in value]
        await self.store.set_cache(
            cache_key,
            json.dumps(payload),
            epoch=epoch,
            project_id=str(project_id),
        )
        return value

    async def find_unused_keywords(self, project_id: UUID) -> list[EntityRef]:
        async def build() -> list[EntityRef]:
            keywords = await self.store.list_entities(
                project_id=project_id,
                kind=EntityKind.KEYWORD.value,
            )
            call_edges = await self.store.list_edges(
                project_id=project_id,
                edge_kind=EdgeKind.CALLS.value,
            )
            kw_by_norm: dict[str, list[SemanticEntity]] = defaultdict(list)
            arg_names_by_id: dict[str, list[str]] = {}
            for kw in keywords:
                kw_by_norm[kw.name_normalized].append(kw)
                arg_names_by_id[kw.id] = parse_keyword_arg_names(kw.detail)

            used: set[str] = set()

            def mark_by_name(raw_name: str, normalized: str | None = None) -> None:
                for key in keyword_lookup_keys(raw_name, normalized):
                    for match in kw_by_norm.get(key, []):
                        used.add(match.id)

            def resolve_arg_names(edge) -> list[str]:
                if edge.target_id and edge.target_id in arg_names_by_id:
                    return arg_names_by_id[edge.target_id]
                # Unbound call — use a unique definition's Arguments when unambiguous.
                for key in keyword_lookup_keys(
                    edge.target_name,
                    edge.target_name_normalized or None,
                ):
                    matches = kw_by_norm.get(key, [])
                    if len(matches) == 1:
                        return arg_names_by_id.get(matches[0].id, [])
                return []

            for edge in call_edges:
                if edge.target_id:
                    used.add(edge.target_id)
                if edge.target_name:
                    mark_by_name(edge.target_name, edge.target_name_normalized or None)

                args = decode_call_context(edge.context)
                if not args:
                    continue
                outer_norm = (
                    edge.target_name_normalized
                    or normalize_keyword_name(edge.target_name)
                )
                outer_has_keyword = "keyword" in outer_norm
                positional_arg_names = resolve_arg_names(edge)

                for index, arg in enumerate(args):
                    arg_name, arg_val = split_named_argument(arg)
                    if not looks_like_keyword_literal(arg_val):
                        continue
                    # Same heuristic as robotframework-find-unused:
                    # count when outer name or the formal/named arg mentions "keyword".
                    if not outer_has_keyword:
                        formal = arg_name
                        if formal is None and index < len(positional_arg_names):
                            formal = positional_arg_names[index]
                        if formal is None or "keyword" not in formal.casefold():
                            continue
                    mark_by_name(arg_val)

            return [_entity_ref(kw) for kw in keywords if kw.id not in used]

        return await self._cached_models(project_id, "unused_keywords", build, EntityRef)

    async def find_unused_resources(self, project_id: UUID) -> list[EntityRef]:
        async def build() -> list[EntityRef]:
            resources = await self.store.list_entities(
                project_id=project_id,
                kind=EntityKind.RESOURCE.value,
            )
            files = await self.store.list_entities(
                project_id=project_id,
                kind=EntityKind.FILE.value,
            )
            import_edges = await self.store.list_edges(
                project_id=project_id,
                edge_kind=EdgeKind.IMPORTS_RESOURCE.value,
            )
            file_by_id = {f.id: f for f in files}
            resource_id_by_path = {
                str(res.file_path.resolve()): res.id for res in resources
            }
            used: set[str] = set()
            for edge in import_edges:
                if not edge.target_id:
                    continue
                used.add(edge.target_id)
                # Legacy / fallback bindings may point at FILE; map to RESOURCE.
                file_ent = file_by_id.get(edge.target_id)
                if file_ent is not None:
                    rid = resource_id_by_path.get(str(file_ent.file_path.resolve()))
                    if rid:
                        used.add(rid)
            return [_entity_ref(res) for res in resources if res.id not in used]

        return await self._cached_models(project_id, "unused_resources", build, EntityRef)

    async def find_duplicate_keywords(self, project_id: UUID) -> list[list[EntityRef]]:
        async def build() -> list[list[EntityRef]]:
            keywords = await self.store.list_entities(
                project_id=project_id,
                kind=EntityKind.KEYWORD.value,
            )
            groups: dict[str, list[SemanticEntity]] = defaultdict(list)
            for kw in keywords:
                groups[kw.name_normalized].append(kw)
            return [
                [_entity_ref(item) for item in group]
                for group in groups.values()
                if len(group) > 1
            ]

        return await self._cached_models(
            project_id,
            "duplicate_keywords",
            build,
            EntityRef,
            nested=True,
        )

    async def find_missing_imports(self, project_id: UUID) -> list[EdgeRef]:
        async def build() -> list[EdgeRef]:
            edges = await self.store.list_edges(project_id=project_id)
            missing: list[EdgeRef] = []
            for edge in edges:
                if edge.edge_kind not in {
                    EdgeKind.IMPORTS_RESOURCE,
                    EdgeKind.IMPORTS_VARIABLES,
                }:
                    continue
                if edge.target_id is not None:
                    continue
                if "${" in edge.target_name:
                    continue
                # Variables *.py / *.yaml (and any path import) may exist on disk
                # without an analysis entity — do not flag those as missing.
                if import_path_exists_on_disk(edge.target_name, edge.source_file):
                    continue
                source = await self.store.get_entity(edge.source_id)
                missing.append(
                    EdgeRef(
                        edge_kind=edge.edge_kind.value,
                        source=_entity_ref(source) if source else None,
                        target=None,
                        source_file=str(edge.source_file),
                        source_line=edge.source_line,
                        source_column=edge.source_column,
                        target_name=edge.target_name,
                        confidence=edge.confidence.value,
                        context=edge.context,
                    ),
                )
            return missing

        results = await self._cached_models(project_id, "missing_imports", build, EdgeRef)
        # Epoch-scoped SQLite cache can outlive logic fixes (and newly created
        # variable files). Always re-check the filesystem before surfacing.
        return [
            edge
            for edge in results
            if not import_path_exists_on_disk(edge.target_name, edge.source_file or "")
        ]

    async def find_keyword_callers(self, project_id: UUID, keyword: str) -> list[EdgeRef]:
        norm = normalize_keyword_name(keyword)
        matches = await self.store.find_entities_by_normalized_name(
            norm,
            project_id=project_id,
            kinds=[EntityKind.KEYWORD.value],
        )
        if not matches:
            return []
        target_ids = {m.id for m in matches}
        edges = await self.store.list_edges(
            project_id=project_id,
            edge_kind=EdgeKind.CALLS.value,
        )
        out: list[EdgeRef] = []
        for edge in edges:
            if edge.target_id not in target_ids and edge.target_name_normalized != norm:
                continue
            source = await self.store.get_entity(edge.source_id)
            target = await self.store.get_entity(edge.target_id) if edge.target_id else None
            out.append(
                EdgeRef(
                    edge_kind=edge.edge_kind.value,
                    source=_entity_ref(source) if source else None,
                    target=_entity_ref(target) if target else None,
                    source_file=str(edge.source_file),
                    source_line=edge.source_line,
                    source_column=edge.source_column,
                    target_name=edge.target_name,
                    confidence=edge.confidence.value,
                    context=edge.context,
                ),
            )
        return out

    async def find_keyword_callees(self, project_id: UUID, keyword: str) -> list[EdgeRef]:
        norm = normalize_keyword_name(keyword)
        matches = await self.store.find_entities_by_normalized_name(
            norm,
            project_id=project_id,
            kinds=[EntityKind.KEYWORD.value],
        )
        if not matches:
            return []
        source_ids = {m.id for m in matches}
        edges = await self.store.list_edges(
            project_id=project_id,
            edge_kind=EdgeKind.CALLS.value,
        )
        out: list[EdgeRef] = []
        for edge in edges:
            if edge.source_id not in source_ids:
                continue
            source = await self.store.get_entity(edge.source_id)
            target = await self.store.get_entity(edge.target_id) if edge.target_id else None
            out.append(
                EdgeRef(
                    edge_kind=edge.edge_kind.value,
                    source=_entity_ref(source) if source else None,
                    target=_entity_ref(target) if target else None,
                    source_file=str(edge.source_file),
                    source_line=edge.source_line,
                    source_column=edge.source_column,
                    target_name=edge.target_name,
                    confidence=edge.confidence.value,
                    context=edge.context,
                ),
            )
        return out

    async def dependency_graph(self, project_id: UUID) -> list[DependencyNode]:
        async def build() -> list[DependencyNode]:
            suites = await self.store.list_entities(
                project_id=project_id,
                kind=EntityKind.SUITE.value,
            )
            resources = await self.store.list_entities(
                project_id=project_id,
                kind=EntityKind.RESOURCE.value,
            )
            nodes = {
                e.id: DependencyNode(
                    id=e.id,
                    kind=e.kind.value,
                    name=e.name,
                    file_path=str(e.file_path),
                )
                for e in [*suites, *resources]
            }
            for edge in await self.store.list_edges(project_id=project_id):
                if edge.edge_kind not in {
                    EdgeKind.IMPORTS_RESOURCE,
                    EdgeKind.IMPORTS_LIBRARY,
                    EdgeKind.IMPORTS_VARIABLES,
                }:
                    continue
                src = nodes.get(edge.source_id)
                if src is None:
                    continue
                label = edge.target_name
                if edge.target_id and edge.target_id in nodes:
                    label = nodes[edge.target_id].name
                    nodes[edge.target_id].imported_by.append(src.id)
                src.imports.append(label)
            return list(nodes.values())

        return await self._cached_models(
            project_id,
            "dependency_graph",
            build,
            DependencyNode,
        )

    async def affected_tests(
        self,
        project_id: UUID,
        *,
        changed_files: list[str] | None = None,
        changed_symbols: list[str] | None = None,
    ) -> list[EntityRef]:
        """Reverse call-graph impact: tests that (transitively) call changed keywords."""
        seed_ids: set[str] = set()
        if changed_symbols:
            for name in changed_symbols:
                norm = normalize_keyword_name(name)
                for ent in await self.store.find_entities_by_normalized_name(
                    norm,
                    project_id=project_id,
                    kinds=[EntityKind.KEYWORD.value, EntityKind.TEST_CASE.value],
                ):
                    seed_ids.add(ent.id)
        if changed_files:
            for raw in changed_files:
                path = str(Path(raw).resolve())
                for ent in await self.store.list_entities(project_id=project_id):
                    if str(ent.file_path.resolve()) == path and ent.kind in {
                        EntityKind.KEYWORD,
                        EntityKind.TEST_CASE,
                        EntityKind.RESOURCE,
                        EntityKind.SUITE,
                    }:
                        seed_ids.add(ent.id)

        if not seed_ids:
            return []

        # Build reverse adjacency: callee -> callers (via CALLS)
        reverse: dict[str, set[str]] = defaultdict(set)
        for edge in await self.store.list_edges(
            project_id=project_id,
            edge_kind=EdgeKind.CALLS.value,
        ):
            if edge.target_id:
                reverse[edge.target_id].add(edge.source_id)

        # Resource import reverse: resource -> importers
        for edge in await self.store.list_edges(
            project_id=project_id,
            edge_kind=EdgeKind.IMPORTS_RESOURCE.value,
        ):
            if edge.target_id:
                reverse[edge.target_id].add(edge.source_id)

        seen: set[str] = set()
        stack = list(seed_ids)
        while stack:
            current = stack.pop()
            if current in seen:
                continue
            seen.add(current)
            for caller in reverse.get(current, ()):
                if caller not in seen:
                    stack.append(caller)

        tests = await self.store.list_entities(
            project_id=project_id,
            kind=EntityKind.TEST_CASE.value,
        )
        return [_entity_ref(t) for t in tests if t.id in seen]

    async def variable_references(self, project_id: UUID, variable: str) -> list[EdgeRef]:
        norm = normalize_variable_name(variable)
        matches = await self.store.find_entities_by_normalized_name(
            norm,
            project_id=project_id,
            kinds=[EntityKind.VARIABLE.value],
        )
        target_ids = {m.id for m in matches}
        edges = await self.store.list_edges(
            project_id=project_id,
            edge_kind=EdgeKind.REFERENCES_VARIABLE.value,
        )
        out: list[EdgeRef] = []
        for edge in edges:
            if edge.target_id not in target_ids and edge.target_name_normalized != norm:
                continue
            source = await self.store.get_entity(edge.source_id)
            target = await self.store.get_entity(edge.target_id) if edge.target_id else None
            out.append(
                EdgeRef(
                    edge_kind=edge.edge_kind.value,
                    source=_entity_ref(source) if source else None,
                    target=_entity_ref(target) if target else None,
                    source_file=str(edge.source_file),
                    source_line=edge.source_line,
                    source_column=edge.source_column,
                    target_name=edge.target_name,
                    confidence=edge.confidence.value,
                    context=edge.context,
                ),
            )
        return out

    async def library_usage(
        self,
        project_id: UUID,
        library: str | None = None,
    ) -> list[EdgeRef]:
        edges = await self.store.list_edges(
            project_id=project_id,
            edge_kind=EdgeKind.IMPORTS_LIBRARY.value,
        )
        out: list[EdgeRef] = []
        want = normalize_keyword_name(library) if library else None
        for edge in edges:
            if want and edge.target_name_normalized != want:
                continue
            source = await self.store.get_entity(edge.source_id)
            target = await self.store.get_entity(edge.target_id) if edge.target_id else None
            out.append(
                EdgeRef(
                    edge_kind=edge.edge_kind.value,
                    source=_entity_ref(source) if source else None,
                    target=_entity_ref(target) if target else None,
                    source_file=str(edge.source_file),
                    source_line=edge.source_line,
                    source_column=edge.source_column,
                    target_name=edge.target_name,
                    confidence=edge.confidence.value,
                    context=edge.context,
                ),
            )
        return out

    async def keyword_usage_statistics(self, project_id: UUID) -> list[UsageStat]:
        async def build() -> list[UsageStat]:
            keywords = await self.store.list_entities(
                project_id=project_id,
                kind=EntityKind.KEYWORD.value,
            )
            calls = await self.store.list_edges(
                project_id=project_id,
                edge_kind=EdgeKind.CALLS.value,
            )
            callers: dict[str, int] = defaultdict(int)
            callees: dict[str, int] = defaultdict(int)
            low_conf: dict[str, int] = defaultdict(int)
            for edge in calls:
                if edge.target_id:
                    callers[edge.target_id] += 1
                if edge.confidence == BindingConfidence.LOW:
                    low_conf[edge.source_id] += 1
                callees[edge.source_id] += 1
            return [
                UsageStat(
                    entity=_entity_ref(kw),
                    callers=callers.get(kw.id, 0),
                    callees=callees.get(kw.id, 0),
                    low_confidence_refs=low_conf.get(kw.id, 0),
                )
                for kw in keywords
            ]

        return await self._cached_models(
            project_id,
            "keyword_usage_statistics",
            build,
            UsageStat,
        )
