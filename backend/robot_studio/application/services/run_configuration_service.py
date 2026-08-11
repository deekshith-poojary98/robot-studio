"""CRUD for project-scoped Run Configurations."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from robot_studio.application.services.execution_plan import (
    ExecutionPlanError,
    validate_extra_robot_args,
)
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.domain.models.run_configuration import (
    RunConfiguration,
    RunConfigurationStore,
    RunVariable,
)
from robot_studio.infrastructure.run_configuration.store import (
    RunConfigurationStoreError,
    load_store,
    save_store,
)

UNSET = object()


class RunConfigurationValidationError(Exception):
    def __init__(self, message: str, *, code: str | None = None) -> None:
        super().__init__(message)
        self.code = code


class RunConfigurationService:
    def __init__(self, context: WorkspaceContext) -> None:
        self._context = context

    def _require_project(self):
        workspace = self._context.workspace
        if workspace is None:
            raise RunConfigurationValidationError(
                "Open a project before managing run configurations",
            )
        project = self._context.project
        if project is None:
            raise RunConfigurationValidationError(
                "Open a project before managing run configurations",
            )
        return project

    def _load(self) -> RunConfigurationStore:
        project = self._require_project()
        try:
            return load_store(project.path)
        except RunConfigurationStoreError as exc:
            raise RunConfigurationValidationError(str(exc)) from exc

    def _save(self, store: RunConfigurationStore) -> None:
        project = self._require_project()
        save_store(project.path, store)

    def list_bundle(self) -> tuple[UUID | None, list[RunConfiguration]]:
        store = self._load()
        return store.active_id, list(store.configurations)

    def get(self, configuration_id: UUID) -> RunConfiguration:
        store = self._load()
        for item in store.configurations:
            if item.id == configuration_id:
                return item
        raise RunConfigurationValidationError(
            "Run configuration not found",
            code="configuration_missing",
        )

    def create(
        self,
        *,
        name: str,
        environment_id: UUID | None = None,
        include_tags: list[str] | None = None,
        exclude_tags: list[str] | None = None,
        variables: list[RunVariable] | None = None,
        variable_files: list[str] | None = None,
        extra_robot_args: list[str] | None = None,
        activate: bool = True,
    ) -> RunConfiguration:
        cleaned = self._validated_fields(
            name=name,
            include_tags=include_tags,
            exclude_tags=exclude_tags,
            variables=variables,
            variable_files=variable_files,
            extra_robot_args=extra_robot_args,
        )
        now = datetime.now(UTC)
        item = RunConfiguration(
            id=uuid4(),
            name=cleaned["name"],
            environment_id=environment_id,
            include_tags=cleaned["include_tags"],
            exclude_tags=cleaned["exclude_tags"],
            variables=cleaned["variables"],
            variable_files=cleaned["variable_files"],
            extra_robot_args=cleaned["extra_robot_args"],
            created_at=now,
            updated_at=now,
        )
        store = self._load()
        self._assert_unique_name(store, item.name, ignore_id=None)
        store.configurations.append(item)
        if activate or store.active_id is None:
            store.active_id = item.id
        self._save(store)
        return item

    def update(
        self,
        configuration_id: UUID,
        *,
        name: str | None = None,
        environment_id: UUID | None | object = UNSET,
        include_tags: list[str] | None = None,
        exclude_tags: list[str] | None = None,
        variables: list[RunVariable] | None = None,
        variable_files: list[str] | None = None,
        extra_robot_args: list[str] | None = None,
    ) -> RunConfiguration:
        store = self._load()
        current = self._find(store, configuration_id)
        merged_name = current.name if name is None else name
        cleaned = self._validated_fields(
            name=merged_name,
            include_tags=current.include_tags if include_tags is None else include_tags,
            exclude_tags=current.exclude_tags if exclude_tags is None else exclude_tags,
            variables=current.variables if variables is None else variables,
            variable_files=current.variable_files if variable_files is None else variable_files,
            extra_robot_args=(
                current.extra_robot_args if extra_robot_args is None else extra_robot_args
            ),
        )
        self._assert_unique_name(store, cleaned["name"], ignore_id=configuration_id)
        env_id = current.environment_id if environment_id is UNSET else environment_id
        updated = current.model_copy(
            update={
                "name": cleaned["name"],
                "environment_id": env_id,
                "include_tags": cleaned["include_tags"],
                "exclude_tags": cleaned["exclude_tags"],
                "variables": cleaned["variables"],
                "variable_files": cleaned["variable_files"],
                "extra_robot_args": cleaned["extra_robot_args"],
                "updated_at": datetime.now(UTC),
            },
        )
        store.configurations = [
            updated if item.id == configuration_id else item
            for item in store.configurations
        ]
        self._save(store)
        return updated

    def delete(self, configuration_id: UUID) -> None:
        store = self._load()
        self._find(store, configuration_id)
        store.configurations = [
            item for item in store.configurations if item.id != configuration_id
        ]
        if store.active_id == configuration_id:
            store.active_id = None
        self._save(store)

    def duplicate(self, configuration_id: UUID) -> RunConfiguration:
        store = self._load()
        source = self._find(store, configuration_id)
        now = datetime.now(UTC)
        name = self._copy_name(store, source.name)
        item = source.model_copy(
            update={
                "id": uuid4(),
                "name": name,
                "created_at": now,
                "updated_at": now,
            },
        )
        store.configurations.append(item)
        self._save(store)
        return item

    def activate(self, configuration_id: UUID | None) -> UUID | None:
        store = self._load()
        if configuration_id is not None:
            self._find(store, configuration_id)
        store.active_id = configuration_id
        self._save(store)
        return store.active_id

    @staticmethod
    def _find(store: RunConfigurationStore, configuration_id: UUID) -> RunConfiguration:
        for item in store.configurations:
            if item.id == configuration_id:
                return item
        raise RunConfigurationValidationError(
            "Run configuration not found",
            code="configuration_missing",
        )

    @staticmethod
    def _assert_unique_name(
        store: RunConfigurationStore,
        name: str,
        *,
        ignore_id: UUID | None,
    ) -> None:
        for item in store.configurations:
            if ignore_id is not None and item.id == ignore_id:
                continue
            if item.name.casefold() == name.casefold():
                raise RunConfigurationValidationError(
                    f"A run configuration named '{name}' already exists",
                    code="duplicate_name",
                )

    @staticmethod
    def _copy_name(store: RunConfigurationStore, source_name: str) -> str:
        existing = {item.name.casefold() for item in store.configurations}
        base = f"{source_name} copy"
        if base.casefold() not in existing:
            return base
        index = 2
        while f"{base} {index}".casefold() in existing:
            index += 1
        return f"{base} {index}"

    @staticmethod
    def _validated_fields(
        *,
        name: str,
        include_tags: list[str] | None,
        exclude_tags: list[str] | None,
        variables: list[RunVariable] | None,
        variable_files: list[str] | None,
        extra_robot_args: list[str] | None,
    ) -> dict:
        cleaned_name = name.strip()
        if not cleaned_name:
            raise RunConfigurationValidationError("Name is required")
        extra = [str(tok).strip() for tok in (extra_robot_args or []) if str(tok).strip()]
        try:
            validate_extra_robot_args(extra)
        except ExecutionPlanError as exc:
            raise RunConfigurationValidationError(str(exc), code="invalid_robot_args") from exc
        vars_out: list[RunVariable] = []
        for item in variables or []:
            key = item.key.strip()
            if not key:
                continue
            if ":" in key:
                raise RunConfigurationValidationError(
                    f"Variable name cannot contain ':': '{key}'",
                    code="invalid_variable",
                )
            vars_out.append(RunVariable(key=key, value=item.value))
        return {
            "name": cleaned_name,
            "include_tags": [t.strip() for t in (include_tags or []) if t.strip()],
            "exclude_tags": [t.strip() for t in (exclude_tags or []) if t.strip()],
            "variables": vars_out,
            "variable_files": [p.strip() for p in (variable_files or []) if p.strip()],
            "extra_robot_args": extra,
        }
