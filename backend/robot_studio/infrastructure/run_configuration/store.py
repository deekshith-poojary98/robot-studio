"""Project-scoped run-configurations.json under .robotstudio/."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

from robot_studio.domain.models.run_configuration import (
    RunConfiguration,
    RunConfigurationStore,
    RunVariable,
)
from robot_studio.infrastructure.workspace.filesystem import WORKSPACE_META_DIR

RUN_CONFIGURATIONS_FILE = "run-configurations.json"


def store_path(project_root: Path) -> Path:
    return project_root / WORKSPACE_META_DIR / RUN_CONFIGURATIONS_FILE


def empty_store() -> RunConfigurationStore:
    return RunConfigurationStore()


def load_store(project_root: Path) -> RunConfigurationStore:
    path = store_path(project_root)
    if not path.is_file():
        return empty_store()
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RunConfigurationStoreError(
            f"Cannot read run configurations at '{path}': {exc}",
        ) from exc
    if not isinstance(raw, dict):
        raise RunConfigurationStoreError(
            f"Invalid run configurations file at '{path}'",
        )
    return _from_dict(raw)


def save_store(project_root: Path, store: RunConfigurationStore) -> None:
    meta = project_root / WORKSPACE_META_DIR
    meta.mkdir(parents=True, exist_ok=True)
    path = store_path(project_root)
    tmp = path.with_suffix(".json.tmp")
    payload = json.dumps(_to_dict(store), indent=2) + "\n"
    tmp.write_text(payload, encoding="utf-8")
    tmp.replace(path)


def _to_dict(store: RunConfigurationStore) -> dict:
    return {
        "version": store.version,
        "active_id": str(store.active_id) if store.active_id else None,
        "configurations": [_config_to_dict(item) for item in store.configurations],
    }


def _config_to_dict(item: RunConfiguration) -> dict:
    return {
        "id": str(item.id),
        "name": item.name,
        "environment_id": str(item.environment_id) if item.environment_id else None,
        "include_tags": list(item.include_tags),
        "exclude_tags": list(item.exclude_tags),
        "variables": [{"key": v.key, "value": v.value} for v in item.variables],
        "variable_files": list(item.variable_files),
        "extra_robot_args": list(item.extra_robot_args),
        "created_at": item.created_at.isoformat(),
        "updated_at": item.updated_at.isoformat(),
    }


def _from_dict(raw: dict) -> RunConfigurationStore:
    configs: list[RunConfiguration] = []
    for item in raw.get("configurations") or []:
        if not isinstance(item, dict):
            continue
        configs.append(_config_from_dict(item))
    active_raw = raw.get("active_id")
    active_id = UUID(str(active_raw)) if active_raw else None
    if active_id is not None and all(c.id != active_id for c in configs):
        active_id = None
    return RunConfigurationStore(
        version=int(raw.get("version") or 1),
        active_id=active_id,
        configurations=configs,
    )


def _config_from_dict(item: dict) -> RunConfiguration:
    created = _parse_dt(item.get("created_at"))
    updated = _parse_dt(item.get("updated_at")) or created
    env_raw = item.get("environment_id")
    variables = []
    for row in item.get("variables") or []:
        if isinstance(row, dict) and str(row.get("key") or "").strip():
            variables.append(
                RunVariable(key=str(row["key"]).strip(), value=str(row.get("value") or "")),
            )
    return RunConfiguration(
        id=UUID(str(item["id"])),
        name=str(item.get("name") or "").strip() or "Untitled",
        environment_id=UUID(str(env_raw)) if env_raw else None,
        include_tags=_string_list(item.get("include_tags")),
        exclude_tags=_string_list(item.get("exclude_tags")),
        variables=variables,
        variable_files=_string_list(item.get("variable_files")),
        extra_robot_args=_string_list(item.get("extra_robot_args")),
        created_at=created or datetime.now(UTC),
        updated_at=updated or datetime.now(UTC),
    )


def _string_list(raw: object) -> list[str]:
    if not isinstance(raw, list):
        return []
    return [str(item).strip() for item in raw if str(item).strip()]


def _parse_dt(raw: object) -> datetime | None:
    if not isinstance(raw, str) or not raw.strip():
        return None
    value = datetime.fromisoformat(raw)
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value


class RunConfigurationStoreError(Exception):
    pass
