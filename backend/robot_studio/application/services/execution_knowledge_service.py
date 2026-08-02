"""Execution knowledge queries + EventBus wiring for ExecutionLinker."""

from __future__ import annotations

from dataclasses import dataclass, field
from statistics import mean, pstdev
from uuid import UUID

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import EventBus, RunDeleted, RunIndexed, Subscription
from robot_studio.domain.interfaces.analysis import AnalysisStore
from robot_studio.domain.models.analysis import BindingConfidence, EntityKind, EntityRef
from robot_studio.domain.models.execution_knowledge import (
    EntityExecutionStats,
    ExecutionHistoryEntry,
    ExecutionKnowledgeSnapshot,
    FlakyCandidate,
    HeatMapEntry,
    LinkedRunInfo,
    SlowEntity,
)
from robot_studio.infrastructure.analysis.execution_linker import ExecutionLinker
from robot_studio.infrastructure.analysis.execution_store import SqliteExecutionKnowledgeStore
from robot_studio.infrastructure.repositories.execution_repository import (
    SqliteExecutionRepository,
)


class ExecutionKnowledgeValidationError(Exception):
    pass


def _entity_ref_from_dict(entity) -> EntityRef:
    return EntityRef(
        id=entity.id,
        kind=entity.kind.value if hasattr(entity.kind, "value") else str(entity.kind),
        name=entity.name,
        file_path=str(entity.file_path),
        line=entity.line,
        column=entity.column,
        documentation=entity.documentation,
        detail=entity.detail,
    )


@dataclass
class ExecutionKnowledgeService:
    """Queryable execution knowledge. FindingProviders can depend on this later."""

    context: WorkspaceContext
    event_bus: EventBus
    analysis_store: AnalysisStore
    execution_store: SqliteExecutionKnowledgeStore
    execution_repository: SqliteExecutionRepository
    linker: ExecutionLinker = field(init=False)
    _subscribed: bool = field(default=False, init=False)
    _unsubs: list[Subscription] = field(default_factory=list, init=False)

    def __post_init__(self) -> None:
        self.linker = ExecutionLinker(
            analysis_store=self.analysis_store,
            execution_store=self.execution_store,
        )

    def start(self) -> None:
        if self._subscribed:
            return
        self._unsubs = [
            self.event_bus.subscribe(RunIndexed, self._on_run_indexed),
            self.event_bus.subscribe(RunDeleted, self._on_run_deleted),
        ]
        self._subscribed = True

    async def stop(self) -> None:
        for sub in self._unsubs:
            sub.unsubscribe()
        self._unsubs.clear()
        self._subscribed = False

    async def _on_run_indexed(self, event: RunIndexed) -> None:
        run = await self.execution_repository.get(event.run_id)
        if run is None:
            return
        await self.linker.link_run(run)

    async def _on_run_deleted(self, event: RunDeleted) -> None:
        await self.execution_store.delete_run(event.run_id)

    async def _require_project(self, project_id: UUID | None) -> UUID:
        if project_id is not None:
            return project_id
        if self.context.project is None:
            raise ExecutionKnowledgeValidationError("No active project")
        return self.context.project.id

    async def _enrich_history(
        self,
        entries: list[ExecutionHistoryEntry],
    ) -> list[ExecutionHistoryEntry]:
        out: list[ExecutionHistoryEntry] = []
        for entry in entries:
            entity = await self.analysis_store.get_entity(entry.entity_id)
            out.append(
                entry.model_copy(
                    update={"entity": _entity_ref_from_dict(entity) if entity else None},
                ),
            )
        return out

    async def snapshot(self, project_id: UUID | None = None) -> ExecutionKnowledgeSnapshot:
        return await self.execution_store.snapshot(await self._require_project(project_id))

    async def link_run(self, run_id: UUID) -> LinkedRunInfo | None:
        run = await self.execution_repository.get(run_id)
        if run is None:
            raise ExecutionKnowledgeValidationError(f"Unknown run: {run_id}")
        return await self.linker.link_run(run)

    async def history_for_keyword(
        self,
        keyword: str,
        project_id: UUID | None = None,
        *,
        limit: int = 50,
    ) -> list[ExecutionHistoryEntry]:
        pid = await self._require_project(project_id)
        entity = await self._find_keyword(pid, keyword)
        if entity is None:
            return []
        return await self._enrich_history(
            await self.execution_store.history_for_entity(
                pid,
                entity.id,
                limit=limit,
                role="callee",
            ),
        )

    async def history_for_test(
        self,
        test: str,
        project_id: UUID | None = None,
        *,
        limit: int = 50,
    ) -> list[ExecutionHistoryEntry]:
        pid = await self._require_project(project_id)
        entity = await self._find_test(pid, test)
        if entity is None:
            return []
        return await self._enrich_history(
            await self.execution_store.history_for_entity(
                pid,
                entity.id,
                limit=limit,
                role="subject",
            ),
        )

    async def last_failures(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 50,
    ) -> list[ExecutionHistoryEntry]:
        pid = await self._require_project(project_id)
        return await self._enrich_history(
            await self.execution_store.last_failures(pid, limit=limit),
        )

    async def slowest_keywords(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 20,
    ) -> list[SlowEntity]:
        return await self._slowest(project_id, kind=EntityKind.KEYWORD, limit=limit)

    async def slowest_tests(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 20,
    ) -> list[SlowEntity]:
        return await self._slowest(project_id, kind=EntityKind.TEST_CASE, limit=limit)

    async def _slowest(
        self,
        project_id: UUID | None,
        *,
        kind: EntityKind,
        limit: int,
    ) -> list[SlowEntity]:
        pid = await self._require_project(project_id)
        stats = await self.execution_store.get_stats(pid)
        entities = {
            e.id: e
            for e in await self.analysis_store.list_entities(project_id=pid, kind=kind.value)
        }
        ranked: list[SlowEntity] = []
        for st in stats:
            ent = entities.get(st.entity_id)
            if ent is None:
                continue
            ranked.append(
                SlowEntity(
                    entity=_entity_ref_from_dict(ent),
                    average_duration_ms=st.average_duration_ms,
                    total_duration_ms=st.total_duration_ms,
                    execution_count=st.execution_count,
                ),
            )
        ranked.sort(key=lambda s: s.average_duration_ms, reverse=True)
        return ranked[:limit]

    async def most_executed_keywords(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 20,
    ) -> list[EntityExecutionStats]:
        pid = await self._require_project(project_id)
        keywords = {
            e.id
            for e in await self.analysis_store.list_entities(
                project_id=pid,
                kind=EntityKind.KEYWORD.value,
            )
        }
        stats = [s for s in await self.execution_store.get_stats(pid) if s.entity_id in keywords]
        stats.sort(key=lambda s: s.execution_count, reverse=True)
        return stats[:limit]

    async def never_executed_keywords(
        self,
        project_id: UUID | None = None,
    ) -> list[EntityRef]:
        pid = await self._require_project(project_id)
        keywords = await self.analysis_store.list_entities(
            project_id=pid,
            kind=EntityKind.KEYWORD.value,
        )
        executed = {
            s.entity_id
            for s in await self.execution_store.get_stats(pid)
            if s.execution_count > 0
        }
        return [_entity_ref_from_dict(k) for k in keywords if k.id not in executed]

    async def execution_heat_map(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 100,
    ) -> list[HeatMapEntry]:
        pid = await self._require_project(project_id)
        stats = await self.execution_store.get_stats(pid)
        out: list[HeatMapEntry] = []
        for st in stats:
            entity = await self.analysis_store.get_entity(st.entity_id)
            if entity is None:
                continue
            fail_rate = (st.fail_count / st.execution_count) if st.execution_count else 0.0
            # Heat: failures weighted by frequency
            heat = fail_rate * (1.0 + min(st.execution_count, 50) / 50.0)
            out.append(
                HeatMapEntry(
                    entity=_entity_ref_from_dict(entity),
                    execution_count=st.execution_count,
                    fail_count=st.fail_count,
                    fail_rate=fail_rate,
                    heat_score=heat,
                    average_duration_ms=st.average_duration_ms,
                    last_failure=st.last_failure,
                ),
            )
        out.sort(key=lambda h: h.heat_score, reverse=True)
        return out[:limit]

    async def flaky_candidates(
        self,
        project_id: UUID | None = None,
        *,
        limit: int = 50,
        min_runs: int = 4,
    ) -> list[FlakyCandidate]:
        """Deterministic flaky heuristics — no ML."""
        pid = await self._require_project(project_id)
        stats = await self.execution_store.get_stats(pid)
        candidates: list[FlakyCandidate] = []
        for st in stats:
            if st.execution_count < min_runs:
                continue
            entity = await self.analysis_store.get_entity(st.entity_id)
            if entity is None:
                continue
            if entity.kind not in {EntityKind.TEST_CASE, EntityKind.KEYWORD}:
                continue
            history = await self.execution_store.history_for_entity(
                pid,
                st.entity_id,
                limit=30,
                role="subject" if entity.kind == EntityKind.TEST_CASE else "callee",
            )
            if len(history) < min_runs:
                continue
            statuses = [h.status.upper() for h in reversed(history)]
            durations = [h.duration_ms for h in history if h.duration_ms > 0]
            reasons: list[str] = []
            fail_rate = st.fail_count / st.execution_count if st.execution_count else 0.0

            # Alternating pass/fail
            flips = sum(
                1 for i in range(1, len(statuses)) if statuses[i] != statuses[i - 1]
            )
            alternating_score = flips / max(len(statuses) - 1, 1)
            if alternating_score >= 0.5 and 0.2 <= fail_rate <= 0.8:
                reasons.append("alternating_pass_fail")

            # Intermittent failures
            if st.fail_count >= 2 and 0.15 <= fail_rate <= 0.85:
                reasons.append("intermittent_failures")

            # Inconsistent duration (coefficient of variation)
            duration_cv = 0.0
            if len(durations) >= 3:
                m = mean(durations)
                if m > 0:
                    duration_cv = pstdev(durations) / m
                    if duration_cv >= 0.75:
                        reasons.append("inconsistent_duration")

            # Frequent retries: FAIL followed by PASS within consecutive history
            retries = sum(
                1
                for i in range(1, len(statuses))
                if statuses[i - 1] == "FAIL" and statuses[i] == "PASS"
            )
            if retries >= 2:
                reasons.append("frequent_retries")

            if not reasons:
                continue

            # Confidence from how many signals fire
            if len(reasons) >= 3:
                confidence = BindingConfidence.HIGH
            elif len(reasons) == 2:
                confidence = BindingConfidence.MEDIUM
            else:
                confidence = BindingConfidence.LOW

            candidates.append(
                FlakyCandidate(
                    entity=_entity_ref_from_dict(entity),
                    confidence=confidence,
                    reasons=reasons,
                    fail_rate=fail_rate,
                    execution_count=st.execution_count,
                    alternating_score=alternating_score,
                    duration_cv=duration_cv,
                    metadata={"retry_transitions": retries},
                ),
            )
        candidates.sort(
            key=lambda c: (len(c.reasons), c.fail_rate, c.execution_count),
            reverse=True,
        )
        return candidates[:limit]

    async def _find_keyword(self, project_id: UUID, name: str):
        from robot_studio.infrastructure.analysis.normalize import normalize_keyword_name

        matches = await self.analysis_store.find_entities_by_normalized_name(
            normalize_keyword_name(name),
            project_id=project_id,
            kinds=[EntityKind.KEYWORD.value],
        )
        return matches[0] if matches else None

    async def _find_test(self, project_id: UUID, name: str):
        from robot_studio.infrastructure.analysis.normalize import normalize_keyword_name

        matches = await self.analysis_store.find_entities_by_normalized_name(
            normalize_keyword_name(name),
            project_id=project_id,
            kinds=[EntityKind.TEST_CASE.value],
        )
        return matches[0] if matches else None
