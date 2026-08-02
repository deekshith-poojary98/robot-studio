"""Link Robot Framework output.xml traces onto semantic entity IDs."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

from robot_studio.domain.interfaces.analysis import AnalysisStore
from robot_studio.domain.models.analysis import BindingConfidence, EntityKind
from robot_studio.domain.models.execution_knowledge import (
    ExecutionEdgeKind,
    ExecutionEdgeRef,
    ExecutionHistoryEntry,
    LinkedRunInfo,
)
from robot_studio.domain.models import ExecutionRun
from robot_studio.infrastructure.analysis.execution_store import SqliteExecutionKnowledgeStore
from robot_studio.infrastructure.analysis.normalize import normalize_keyword_name
from robot_studio.infrastructure.execution.execution_trace import (
    ExecutionTrace,
    KeywordStep,
    flatten_keyword_steps,
    iter_tests,
    parse_execution_trace,
)


@dataclass
class ExecutionLinker:
    """Consumes output.xml + semantic graph; never creates duplicate entities."""

    analysis_store: AnalysisStore
    execution_store: SqliteExecutionKnowledgeStore

    async def link_run(self, run: ExecutionRun) -> LinkedRunInfo | None:
        if run.output_xml is None or not Path(run.output_xml).is_file():
            return None
        if await self.execution_store.is_run_linked(run.id):
            # Idempotent — already linked
            linked = await self.execution_store.linked_runs(run.project_id)
            for item in linked:
                if item.run_id == str(run.id):
                    return item
            return None

        trace = parse_execution_trace(run.output_xml)
        if trace is None:
            return None

        version = await self.analysis_store.get_graph_version(run.project_id)
        executed_at = run.finished_at or run.started_at or datetime.now(UTC)
        project_id = str(run.project_id)
        run_id = str(run.id)

        test_count = 0
        keyword_steps = 0

        for suite, test in iter_tests(trace):
            test_count += 1
            test_entity = await self._resolve_test(
                project_id=run.project_id,
                name=test.name,
                source=test.source or suite.source,
            )
            suite_entity = await self._resolve_suite(
                project_id=run.project_id,
                source=suite.source,
                name=suite.name,
            )

            if suite_entity is not None:
                await self.execution_store.add_edge(
                    ExecutionEdgeRef(
                        edge_kind=ExecutionEdgeKind.SUITE_EXECUTION,
                        source_id=suite_entity.id,
                        target_id=None,
                        run_id=run_id,
                        target_name=run_id,
                        status=suite.status or test.status,
                        duration_ms=suite.elapsed_ms,
                        confidence=BindingConfidence.EXACT,
                        graph_version=version.graph_version,
                    ),
                    project_id,
                )

            if test_entity is not None:
                conf = BindingConfidence.EXACT
                await self.execution_store.upsert_history(
                    ExecutionHistoryEntry(
                        run_id=run_id,
                        entity_id=test_entity.id,
                        status=test.status,
                        duration_ms=test.elapsed_ms,
                        role="subject",
                        executed_at=executed_at,
                        message=test.message,
                        graph_version=version.graph_version,
                        confidence=conf,
                    ),
                    project_id,
                )
                await self.execution_store.apply_stat_delta(
                    entity_id=test_entity.id,
                    project_id=project_id,
                    status=test.status,
                    duration_ms=test.elapsed_ms,
                    executed_at=executed_at,
                )

            parent_id = test_entity.id if test_entity else None
            flat = flatten_keyword_steps(test.keywords)
            keyword_steps += len(flat)
            for step in flat:
                await self._link_keyword_step(
                    step=step,
                    project_id=run.project_id,
                    project_id_str=project_id,
                    run_id=run_id,
                    parent_id=parent_id,
                    graph_version=version.graph_version,
                    executed_at=executed_at,
                    as_failed=step.status == "FAIL",
                )

        # execution → graph_version
        await self.execution_store.add_edge(
            ExecutionEdgeRef(
                edge_kind=ExecutionEdgeKind.EXECUTION_GRAPH,
                source_id=f"run:{run_id}",
                target_id=None,
                run_id=run_id,
                target_name=version.graph_version,
                status=run.status.value if hasattr(run.status, "value") else str(run.status),
                confidence=BindingConfidence.EXACT,
                graph_version=version.graph_version,
            ),
            project_id,
        )

        info = LinkedRunInfo(
            run_id=run_id,
            project_id=project_id,
            graph_version=version.graph_version,
            incremental_revision=version.incremental_revision,
            linked_at=datetime.now(UTC),
            test_count=test_count,
            keyword_steps=keyword_steps,
        )
        await self.execution_store.record_linked_run(info)
        return info

    async def _link_keyword_step(
        self,
        *,
        step: KeywordStep,
        project_id: UUID,
        project_id_str: str,
        run_id: str,
        parent_id: str | None,
        graph_version: str,
        executed_at: datetime,
        as_failed: bool,
    ) -> None:
        if not step.name:
            return
        # Skip BuiltIn / library-owned steps for entity stats unless user keyword exists
        entity = await self._resolve_keyword(project_id, step.name)
        confidence = BindingConfidence.HIGH if entity else BindingConfidence.LOW
        target_id = entity.id if entity else None

        if parent_id is not None:
            await self.execution_store.add_edge(
                ExecutionEdgeRef(
                    edge_kind=ExecutionEdgeKind.EXECUTED_KEYWORD,
                    source_id=parent_id,
                    target_id=target_id,
                    run_id=run_id,
                    target_name=step.name,
                    status=step.status,
                    duration_ms=step.elapsed_ms,
                    confidence=confidence,
                    graph_version=graph_version,
                ),
                project_id_str,
            )
            if as_failed or step.status == "FAIL":
                await self.execution_store.add_edge(
                    ExecutionEdgeRef(
                        edge_kind=ExecutionEdgeKind.FAILED_KEYWORD,
                        source_id=parent_id,
                        target_id=target_id,
                        run_id=run_id,
                        target_name=step.name,
                        status=step.status,
                        duration_ms=step.elapsed_ms,
                        confidence=confidence,
                        graph_version=graph_version,
                    ),
                    project_id_str,
                )

        if entity is None:
            return

        await self.execution_store.upsert_history(
            ExecutionHistoryEntry(
                run_id=run_id,
                entity_id=entity.id,
                status=step.status,
                duration_ms=step.elapsed_ms,
                role="callee",
                executed_at=executed_at,
                graph_version=graph_version,
                confidence=confidence,
            ),
            project_id_str,
        )
        # Subject-level stats for keywords: count each run appearance once via callee role
        # Use apply_stat_delta for keyword frequency / duration aggregates
        await self.execution_store.apply_stat_delta(
            entity_id=entity.id,
            project_id=project_id_str,
            status=step.status,
            duration_ms=step.elapsed_ms,
            executed_at=executed_at,
        )

    async def _resolve_test(self, *, project_id: UUID, name: str, source: str):
        norm = normalize_keyword_name(name)
        candidates = await self.analysis_store.find_entities_by_normalized_name(
            norm,
            project_id=project_id,
            kinds=[EntityKind.TEST_CASE.value],
        )
        if not candidates:
            return None
        if source:
            src = str(Path(source).resolve())
            for c in candidates:
                if str(c.file_path.resolve()) == src:
                    return c
        return candidates[0]

    async def _resolve_suite(self, *, project_id: UUID, source: str, name: str):
        if source:
            src = str(Path(source).resolve())
            for kind in (EntityKind.SUITE.value, EntityKind.RESOURCE.value, EntityKind.FILE.value):
                entities = await self.analysis_store.list_entities(
                    project_id=project_id,
                    kind=kind,
                )
                for ent in entities:
                    if str(ent.file_path.resolve()) == src:
                        if kind == EntityKind.SUITE.value or ent.name_normalized == normalize_keyword_name(
                            name or Path(source).stem,
                        ):
                            return ent
                for ent in entities:
                    if str(ent.file_path.resolve()) == src and kind == EntityKind.SUITE.value:
                        return ent
        norm = normalize_keyword_name(name or Path(source).stem if source else "")
        if not norm:
            return None
        matches = await self.analysis_store.find_entities_by_normalized_name(
            norm,
            project_id=project_id,
            kinds=[EntityKind.SUITE.value],
        )
        return matches[0] if matches else None

    async def _resolve_keyword(self, project_id: UUID, name: str):
        norm = normalize_keyword_name(name)
        matches = await self.analysis_store.find_entities_by_normalized_name(
            norm,
            project_id=project_id,
            kinds=[EntityKind.KEYWORD.value],
        )
        if not matches:
            return None
        if len(matches) == 1:
            return matches[0]
        # Ambiguous — still link with LOW confidence at caller; pick first
        return matches[0]
