"""Built-in inspections — each returns uniform ``Finding`` rows for Doctor."""

from __future__ import annotations

import hashlib
from collections import defaultdict
from uuid import UUID

from robot_studio.domain.interfaces.analysis import AnalysisEngine, Inspection
from robot_studio.domain.models.analysis import (
    BindingConfidence,
    Finding,
    FindingSeverity,
    InspectionInfo,
)


def _fid(inspection_id: str, *parts: str) -> str:
    raw = "|".join([inspection_id, *parts])
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:20]


class UnusedKeywordInspection(Inspection):
    @property
    def info(self) -> InspectionInfo:
        return InspectionInfo(
            id="unused_keyword",
            title="Potentially unused keyword",
            description=(
                "User keywords with no bound callers in the project call graph. "
                "Conservative — dynamic/shared usage may still exist."
            ),
            default_severity=FindingSeverity.INFO,
        )

    async def run(self, project_id: UUID, engine: AnalysisEngine) -> list[Finding]:
        findings: list[Finding] = []
        for entity in await engine.find_unused_keywords(project_id):
            findings.append(
                Finding(
                    id=_fid(self.info.id, entity.id),
                    inspection_id=self.info.id,
                    severity=FindingSeverity.INFO,
                    message=f"Potentially unused keyword '{entity.name}'",
                    confidence=BindingConfidence.MEDIUM,
                    entity=entity,
                    file_path=entity.file_path,
                    line=entity.line,
                    column=entity.column,
                    metadata={
                        "affected_files": [
                            {
                                "path": entity.file_path,
                                "name": entity.name,
                                "line": entity.line,
                            },
                        ],
                    },
                ),
            )
        return findings


class UnusedResourceInspection(Inspection):
    @property
    def info(self) -> InspectionInfo:
        return InspectionInfo(
            id="unused_resource",
            title="Potentially unused resource",
            description=(
                "Resource files not imported by any suite/resource in the static graph. "
                "Conservative — dynamic loads may still exist."
            ),
            default_severity=FindingSeverity.INFO,
        )

    async def run(self, project_id: UUID, engine: AnalysisEngine) -> list[Finding]:
        findings: list[Finding] = []
        for entity in await engine.find_unused_resources(project_id):
            findings.append(
                Finding(
                    id=_fid(self.info.id, entity.id),
                    inspection_id=self.info.id,
                    severity=FindingSeverity.INFO,
                    message=f"Potentially unused resource '{entity.name}'",
                    confidence=BindingConfidence.MEDIUM,
                    entity=entity,
                    file_path=entity.file_path,
                    line=entity.line,
                    column=entity.column,
                    metadata={
                        "affected_files": [
                            {
                                "path": entity.file_path,
                                "name": entity.name,
                                "line": entity.line,
                            },
                        ],
                    },
                ),
            )
        return findings


class DuplicateKeywordInspection(Inspection):
    @property
    def info(self) -> InspectionInfo:
        return InspectionInfo(
            id="duplicate_keyword",
            title="Duplicate keyword",
            description="Multiple keyword definitions share the same normalized name.",
            default_severity=FindingSeverity.ERROR,
        )

    async def run(self, project_id: UUID, engine: AnalysisEngine) -> list[Finding]:
        findings: list[Finding] = []
        for group in await engine.find_duplicate_keywords(project_id):
            if len(group) < 2:
                continue
            primary = group[0]
            affected = [
                {"path": g.file_path, "name": g.name, "line": g.line}
                for g in group
            ]
            locations = ", ".join(f"{g.file_path}:{g.line}" for g in group)
            findings.append(
                Finding(
                    id=_fid(self.info.id, primary.name, *(g.id for g in group)),
                    inspection_id=self.info.id,
                    severity=FindingSeverity.ERROR,
                    message=(
                        f"Duplicate keyword '{primary.name}' "
                        f"({len(group)} definitions)"
                    ),
                    confidence=BindingConfidence.EXACT,
                    entity=primary,
                    secondary_entities=group[1:],
                    file_path=primary.file_path,
                    line=primary.line,
                    column=primary.column,
                    metadata={
                        "count": len(group),
                        "locations": locations,
                        "affected_files": affected,
                    },
                ),
            )
        return findings


class MissingImportInspection(Inspection):
    @property
    def info(self) -> InspectionInfo:
        return InspectionInfo(
            id="missing_import",
            title="Missing import",
            description="Resource/Variables imports that could not be resolved on disk.",
            default_severity=FindingSeverity.ERROR,
        )

    async def run(self, project_id: UUID, engine: AnalysisEngine) -> list[Finding]:
        findings: list[Finding] = []
        for edge in await engine.find_missing_imports(project_id):
            findings.append(
                Finding(
                    id=_fid(
                        self.info.id,
                        edge.source_file,
                        str(edge.source_line),
                        edge.target_name,
                    ),
                    inspection_id=self.info.id,
                    severity=FindingSeverity.ERROR,
                    message=f"Unresolved import '{edge.target_name}'",
                    confidence=BindingConfidence.LOW,
                    entity=edge.source,
                    file_path=edge.source_file,
                    line=edge.source_line,
                    column=edge.source_column,
                    related_edges=[edge],
                ),
            )
        return findings


class CircularDependencyInspection(Inspection):
    @property
    def info(self) -> InspectionInfo:
        return InspectionInfo(
            id="circular_dependency",
            title="Circular dependency",
            description="Cycles in the resource/suite import graph.",
            default_severity=FindingSeverity.ERROR,
        )

    async def run(self, project_id: UUID, engine: AnalysisEngine) -> list[Finding]:
        nodes = await engine.dependency_graph(project_id)
        by_id = {n.id: n for n in nodes}
        # imported_by is reverse edge: if B listed on A's imports, B.imported_by contains A.id
        adj: dict[str, set[str]] = defaultdict(set)
        for node in nodes:
            for importer_id in node.imported_by:
                adj[importer_id].add(node.id)

        index = 0
        stack: list[str] = []
        on_stack: set[str] = set()
        indices: dict[str, int] = {}
        lowlink: dict[str, int] = {}
        sccs: list[list[str]] = []

        def strongconnect(v: str) -> None:
            nonlocal index
            indices[v] = index
            lowlink[v] = index
            index += 1
            stack.append(v)
            on_stack.add(v)
            for w in adj.get(v, ()):
                if w not in indices:
                    strongconnect(w)
                    lowlink[v] = min(lowlink[v], lowlink[w])
                elif w in on_stack:
                    lowlink[v] = min(lowlink[v], indices[w])
            if lowlink[v] == indices[v]:
                comp: list[str] = []
                while True:
                    w = stack.pop()
                    on_stack.discard(w)
                    comp.append(w)
                    if w == v:
                        break
                if len(comp) > 1 or (len(comp) == 1 and comp[0] in adj.get(comp[0], ())):
                    sccs.append(comp)

        for node_id in by_id:
            if node_id not in indices:
                strongconnect(node_id)

        from robot_studio.domain.models.analysis import EntityRef

        findings: list[Finding] = []
        for comp in sccs:
            entities = [
                EntityRef(
                    id=by_id[nid].id,
                    kind=by_id[nid].kind,
                    name=by_id[nid].name,
                    file_path=by_id[nid].file_path,
                )
                for nid in comp
            ]
            primary = entities[0]
            cycle = " → ".join(e.name for e in entities) + f" → {entities[0].name}"
            affected = [
                {"path": e.file_path, "name": e.name, "line": e.line}
                for e in entities
            ]
            findings.append(
                Finding(
                    id=_fid(self.info.id, *sorted(comp)),
                    inspection_id=self.info.id,
                    severity=FindingSeverity.ERROR,
                    message=f"Circular Resource import: {cycle}",
                    confidence=BindingConfidence.HIGH,
                    entity=primary,
                    secondary_entities=entities[1:],
                    file_path=primary.file_path,
                    line=primary.line,
                    column=primary.column,
                    metadata={
                        "cycle": [e.id for e in entities],
                        "cycle_path": cycle,
                        "affected_files": affected,
                    },
                ),
            )
        return findings


class LargeKeywordInspection(Inspection):
    """Heuristic smell: keywords that call many other keywords."""

    def __init__(self, threshold: int = 15) -> None:
        self._threshold = threshold

    @property
    def info(self) -> InspectionInfo:
        return InspectionInfo(
            id="large_keyword",
            title="Large keyword",
            description=(
                f"Keywords with {self._threshold}+ outgoing keyword calls "
                "(candidate for extract-keyword)."
            ),
            default_severity=FindingSeverity.HINT,
        )

    async def run(self, project_id: UUID, engine: AnalysisEngine) -> list[Finding]:
        findings: list[Finding] = []
        for stat in await engine.keyword_usage_statistics(project_id):
            if stat.callees < self._threshold:
                continue
            findings.append(
                Finding(
                    id=_fid(self.info.id, stat.entity.id),
                    inspection_id=self.info.id,
                    severity=FindingSeverity.HINT,
                    message=(
                        f"Keyword '{stat.entity.name}' has {stat.callees} outgoing calls "
                        f"(threshold {self._threshold})"
                    ),
                    confidence=BindingConfidence.MEDIUM,
                    entity=stat.entity,
                    file_path=stat.entity.file_path,
                    line=stat.entity.line,
                    column=stat.entity.column,
                    metadata={"callees": stat.callees, "threshold": self._threshold},
                ),
            )
        return findings


def default_inspections() -> list[Inspection]:
    return [
        UnusedKeywordInspection(),
        UnusedResourceInspection(),
        DuplicateKeywordInspection(),
        MissingImportInspection(),
        CircularDependencyInspection(),
        LargeKeywordInspection(),
    ]
