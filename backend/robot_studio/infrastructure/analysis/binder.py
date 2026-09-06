"""Bind unbound semantic edges to entity IDs (Robot Analysis Engine)."""

from __future__ import annotations

from pathlib import Path
from uuid import UUID

from robot_studio.domain.interfaces.analysis import AnalysisStore
from robot_studio.domain.models.analysis import BindingConfidence, EdgeKind, EntityKind
from robot_studio.infrastructure.analysis.embedded_args import (
    matches_embedded_keyword,
)
from robot_studio.infrastructure.analysis.normalize import (
    normalize_keyword_name,
    normalize_variable_name,
    strip_bdd_prefix,
    strip_library_prefix,
)


def import_path_exists_on_disk(import_name: str, source_file: Path | str) -> bool:
    """True when a Resource/Variables import resolves to a real file.

    Analysis only extracts entities from ``.robot`` / ``.resource`` files, so
    ``Variables    ../vars.py`` never gets a bound ``target_id``. Callers must
    still treat existing on-disk imports as resolved.
    """
    if not import_name or "${" in import_name or "@{" in import_name:
        return False
    try:
        candidate = Path(import_name).expanduser()
        if not candidate.is_absolute():
            candidate = (Path(source_file).expanduser().resolve().parent / candidate)
        return candidate.resolve().is_file()
    except OSError:
        return False


class SemanticBinder:
    """Resolves CALLS / IMPORTS_* / REFERENCES_VARIABLE edges within a project."""

    def __init__(self, store: AnalysisStore) -> None:
        self._store = store

    async def rebind_project(self, project_id: UUID) -> int:
        """Bind all unbound edges for *project_id*. Returns number of bindings updated."""
        keywords = await self._store.list_entities(
            project_id=project_id,
            kind=EntityKind.KEYWORD.value,
        )
        variables = await self._store.list_entities(
            project_id=project_id,
            kind=EntityKind.VARIABLE.value,
        )
        resources = await self._store.list_entities(
            project_id=project_id,
            kind=EntityKind.RESOURCE.value,
        )
        files = await self._store.list_entities(
            project_id=project_id,
            kind=EntityKind.FILE.value,
        )

        kw_by_norm: dict[str, list] = {}
        for kw in keywords:
            kw_by_norm.setdefault(kw.name_normalized, []).append(kw)

        var_by_norm = {v.name_normalized: v for v in variables}

        resource_by_path: dict[str, object] = {}
        resource_by_name: dict[str, object] = {}
        for res in resources:
            resource_by_path[str(res.file_path.resolve())] = res
            resource_by_name[normalize_keyword_name(res.file_path.name)] = res
            resource_by_name[normalize_keyword_name(res.name)] = res
        for f in files:
            # Prefer RESOURCE entities for Resource imports. FILE rows are only
            # a fallback (e.g. variables .py/.yaml that have no RESOURCE entity).
            # Overwriting RESOURCE with FILE made every imported .robot resource
            # look unused to find_unused_resources().
            path_key = str(f.file_path.resolve())
            if path_key not in resource_by_path:
                resource_by_path[path_key] = f
            name_key = normalize_keyword_name(f.file_path.name)
            if name_key not in resource_by_name:
                resource_by_name[name_key] = f

        edges = await self._store.list_edges(project_id=project_id)
        updated = 0
        for edge in edges:
            if edge.id is None:
                continue
            if edge.edge_kind == EdgeKind.CALLS:
                target, confidence = self._resolve_keyword(
                    edge.target_name,
                    edge.target_name_normalized,
                    kw_by_norm,
                )
                target_id = target.id if target is not None else None
                if target_id != edge.target_id or edge.confidence != confidence:
                    await self._store.update_edge_binding(
                        edge.id,
                        target_id=target_id,
                        confidence=confidence.value,
                    )
                    updated += 1
            elif edge.edge_kind == EdgeKind.REFERENCES_VARIABLE:
                norm = edge.target_name_normalized or normalize_variable_name(
                    edge.target_name,
                )
                var = var_by_norm.get(norm)
                if var is not None:
                    if edge.target_id != var.id or edge.confidence != BindingConfidence.HIGH:
                        await self._store.update_edge_binding(
                            edge.id,
                            target_id=var.id,
                            confidence=BindingConfidence.HIGH.value,
                        )
                        updated += 1
                elif edge.target_id is not None or edge.confidence != BindingConfidence.LOW:
                    await self._store.update_edge_binding(
                        edge.id,
                        target_id=None,
                        confidence=BindingConfidence.LOW.value,
                    )
                    updated += 1
            elif edge.edge_kind in {
                EdgeKind.IMPORTS_RESOURCE,
                EdgeKind.IMPORTS_VARIABLES,
            }:
                target = self._resolve_import_path(
                    edge.target_name,
                    Path(edge.source_file),
                    resource_by_path,
                    resource_by_name,
                )
                if target is not None:
                    tid = target.id  # type: ignore[attr-defined]
                    if edge.target_id != tid or edge.confidence != BindingConfidence.EXACT:
                        await self._store.update_edge_binding(
                            edge.id,
                            target_id=tid,
                            confidence=BindingConfidence.EXACT.value,
                        )
                        updated += 1
                elif edge.target_id is not None or edge.confidence != BindingConfidence.LOW:
                    await self._store.update_edge_binding(
                        edge.id,
                        target_id=None,
                        confidence=BindingConfidence.LOW.value,
                    )
                    updated += 1
        await self._store.invalidate_cache(project_id)
        return updated

    def _resolve_keyword(
        self,
        raw_name: str,
        normalized: str,
        kw_by_norm: dict[str, list],
    ):
        candidates = [
            (normalized, BindingConfidence.EXACT),
            (
                normalize_keyword_name(strip_library_prefix(raw_name)),
                BindingConfidence.HIGH,
            ),
            (strip_bdd_prefix(normalized), BindingConfidence.MEDIUM),
            (
                strip_bdd_prefix(normalize_keyword_name(strip_library_prefix(raw_name))),
                BindingConfidence.MEDIUM,
            ),
        ]
        seen: set[str] = set()
        for cand, base_confidence in candidates:
            if not cand or cand in seen:
                continue
            seen.add(cand)
            matches = kw_by_norm.get(cand) or []
            if len(matches) == 1:
                confidence = (
                    BindingConfidence.EXACT
                    if cand == normalized and base_confidence == BindingConfidence.EXACT
                    else base_confidence
                )
                return matches[0], confidence
            if len(matches) > 1:
                # Ambiguous — Safe Rename must treat as LOW
                return matches[0], BindingConfidence.LOW
        call_names = [raw_name]
        without_lib = strip_library_prefix(raw_name)
        if without_lib and without_lib != raw_name:
            call_names.append(without_lib)
        for source in list(call_names):
            for prefix in ("Given ", "When ", "Then ", "And ", "But "):
                if source.lower().startswith(prefix.lower()):
                    rest = source[len(prefix) :].lstrip()
                    if rest and rest not in call_names:
                        call_names.append(rest)
                    break
        hits: list = []
        seen_ids: set[str] = set()
        for group in kw_by_norm.values():
            for kw in group:
                if "${" not in (kw.name or ""):
                    continue
                if kw.id in seen_ids:
                    continue
                if any(matches_embedded_keyword(kw.name, call) for call in call_names):
                    seen_ids.add(kw.id)
                    hits.append(kw)
        if len(hits) == 1:
            return hits[0], BindingConfidence.HIGH
        if len(hits) > 1:
            return hits[0], BindingConfidence.LOW
        return None, BindingConfidence.LOW

    def _resolve_import_path(
        self,
        import_name: str,
        source_file: Path,
        by_path: dict,
        by_name: dict,
    ):
        if not import_name:
            return None
        if "${" in import_name or "@{" in import_name:
            return None
        candidate = Path(import_name)
        if not candidate.is_absolute():
            candidate = (source_file.parent / candidate).resolve()
        else:
            candidate = candidate.resolve()
        hit = by_path.get(str(candidate))
        if hit:
            return hit
        return by_name.get(normalize_keyword_name(Path(import_name).name))
