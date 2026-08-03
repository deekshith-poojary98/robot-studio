"""Environment use cases."""

from __future__ import annotations

import tempfile
from datetime import UTC
from pathlib import Path
from uuid import UUID

from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.events import (
    EnvironmentActivated,
    EnvironmentCloned,
    EnvironmentCreated,
    EnvironmentDeleted,
    EnvironmentImported,
    EventBus,
    Subscription,
    WorkspaceOpened,
)
from robot_studio.domain.interfaces.environment import EnvironmentRepository
from robot_studio.domain.models import Environment, WorkspaceSettings
from robot_studio.infrastructure.environment.filesystem import (
    EnvironmentValidationError,
    FilesystemEnvironmentProvider,
)
from robot_studio.infrastructure.environment.python_provider import (
    DiscoveredInterpreter,
    PythonEnvironmentProvider,
)

SortKey = str  # "active" | "name" | "created_at"


class EnvironmentService:
    def __init__(
        self,
        repository: EnvironmentRepository,
        context: WorkspaceContext,
        event_bus: EventBus,
        filesystem: FilesystemEnvironmentProvider | None = None,
        python: PythonEnvironmentProvider | None = None,
    ) -> None:
        self._repository = repository
        self._context = context
        self._event_bus = event_bus
        self._fs = filesystem or FilesystemEnvironmentProvider()
        self._python = python or PythonEnvironmentProvider()
        self._unsubscribes: list[Subscription] = []
        self._started = False

    def start(self) -> None:
        """Subscribe to workspace lifecycle for registry hygiene."""
        if self._started:
            return
        self._unsubscribes = [
            self._event_bus.subscribe(WorkspaceOpened, self._on_workspace_opened),
        ]
        self._started = True

    def stop(self) -> None:
        for subscription in self._unsubscribes:
            subscription.unsubscribe()
        self._unsubscribes.clear()
        self._started = False

    async def _on_workspace_opened(self, event: WorkspaceOpened) -> None:
        # Same absolute path always maps to the same workspace id, so a
        # Finder-deleted project recreated at that path would otherwise revive
        # ghost "missing" rows from the previous life.
        await self.purge_missing_environments(event.workspace_id)

    def _require_workspace(self):
        workspace = self._context.workspace
        if workspace is None:
            raise EnvironmentValidationError(
                "Open a workspace before managing environments",
            )
        return workspace

    async def create_environment(
        self,
        name: str,
        python_interpreter: str | Path,
        *,
        install_robot_framework: bool = False,
    ) -> Environment:
        workspace = self._require_workspace()
        cleaned = self._fs.validate_name(name)
        if self._fs.find_existing_environment_root(workspace.path, cleaned) is not None:
            raise EnvironmentValidationError(
                f"An environment named '{cleaned}' already exists",
            )
        env_root = self._fs.environment_root_for_name(workspace.path, cleaned)

        base_python = Path(python_interpreter).expanduser().resolve()
        self._python.create_venv(base_python, env_root)

        try:
            executables = self._python.resolve_executables(env_root)
            if install_robot_framework:
                self._python.install_robot_framework(executables.python)
                executables = self._python.resolve_executables(env_root)

            python_version = self._python.get_python_version(executables.python)
            is_first = len(await self._repository.list_by_workspace(workspace.id)) == 0

            manifest = self._fs.create_manifest(
                name=cleaned,
                python_version=python_version,
                python_executable=executables.python,
                pip_executable=executables.pip,
                robot_executable=executables.robot,
                path=env_root,
                active=is_first,
            )
            self._fs.write_manifest(env_root, manifest)

            environment = self._from_manifest(workspace.id, manifest)
            await self._repository.create(environment)
            await self._event_bus.publish(
                EnvironmentCreated(
                    workspace_id=workspace.id,
                    environment_id=environment.id,
                ),
            )
            if is_first:
                await self._activate(environment)
            return await self._enrich(environment)
        except Exception:
            if env_root.exists():
                self._fs.delete_directory(env_root)
            raise

    async def import_environment(self, path: str | Path) -> Environment:
        workspace = self._require_workspace()
        env_root = Path(path).expanduser().resolve()

        if not env_root.is_dir():
            raise EnvironmentValidationError(
                f"Directory does not exist: '{env_root}'",
            )
        if not self._fs.is_virtualenv(env_root):
            raise EnvironmentValidationError(
                f"'{env_root}' is not a Python virtual environment "
                "(missing pyvenv.cfg)",
            )

        existing = await self._repository.get_by_path(str(env_root))
        if existing is not None and existing.workspace_id == workspace.id:
            raise EnvironmentValidationError(
                "This environment is already registered in the workspace",
            )

        executables = self._python.resolve_executables(env_root)

        if self._fs.has_manifest(env_root):
            manifest = self._fs.load_manifest(env_root)
            # Keep ids if present, but refresh executable paths.
            manifest = self._fs.create_manifest(
                name=manifest.name,
                python_version=self._python.get_python_version(executables.python),
                python_executable=executables.python,
                pip_executable=executables.pip,
                robot_executable=executables.robot,
                path=env_root,
                active=False,
                environment_id=manifest.id,
                created_at=manifest.created_at,
            )
        else:
            name = env_root.name
            # Avoid clashing with another registered name in the same workspace.
            taken = {
                item.name for item in await self._repository.list_by_workspace(workspace.id)
            }
            candidate = name
            suffix = 2
            while candidate in taken:
                candidate = f"{name}-{suffix}"
                suffix += 1
            manifest = self._fs.create_manifest(
                name=self._fs.validate_name(candidate),
                python_version=self._python.get_python_version(executables.python),
                python_executable=executables.python,
                pip_executable=executables.pip,
                robot_executable=executables.robot,
                path=env_root,
                active=False,
            )

        self._fs.write_manifest(env_root, manifest)
        environment = self._from_manifest(workspace.id, manifest)
        await self._repository.create(environment)
        await self._event_bus.publish(
            EnvironmentImported(
                workspace_id=workspace.id,
                environment_id=environment.id,
            ),
        )

        listed = await self._repository.list_by_workspace(workspace.id)
        if len(listed) == 1:
            await self._activate(environment)
            environment = environment.model_copy(update={"is_active": True})

        return await self._enrich(environment)

    async def list_environments(self, sort: SortKey = "active") -> list[Environment]:
        workspace = self._require_workspace()
        environments = await self._hydrate_from_disk(workspace.id, workspace.path)
        enriched = [await self._enrich(item) for item in environments]
        await self._sync_active_context(enriched)
        return self._sort(enriched, sort)

    async def purge_missing_environments(self, workspace_id: UUID) -> list[UUID]:
        """Drop registry rows whose on-disk roots no longer exist.

        Mid-session list still keeps missing rows (toolbar ``venv · missing``).
        Opening a workspace (or recreating one at the same path) clears ghosts.
        """
        removed: list[UUID] = []
        for environment in await self._repository.list_by_workspace(workspace_id):
            if environment.path.is_dir():
                continue
            await self._repository.delete(environment.id)
            removed.append(environment.id)
            if (
                self._context.workspace is not None
                and self._context.workspace.id == workspace_id
                and self._context.environment_id == environment.id
            ):
                await self._context.clear_active_environment()
            await self._event_bus.publish(
                EnvironmentDeleted(
                    workspace_id=workspace_id,
                    environment_id=environment.id,
                ),
            )
        return removed

    async def purge_workspace_environments(self, workspace_id: UUID) -> int:
        """Remove every environment row for a workspace (root deleted externally)."""
        environments = await self._repository.list_by_workspace(workspace_id)
        if not environments:
            return 0
        count = await self._repository.delete_by_workspace(workspace_id)
        if (
            self._context.workspace is not None
            and self._context.workspace.id == workspace_id
            and self._context.environment is not None
        ):
            await self._context.clear_active_environment()
        for environment in environments:
            await self._event_bus.publish(
                EnvironmentDeleted(
                    workspace_id=workspace_id,
                    environment_id=environment.id,
                ),
            )
        return count

    def list_python_interpreters(self) -> list[DiscoveredInterpreter]:
        """Discover host Python interpreters (does not require an open workspace)."""
        return self._python.discover_interpreters()

    async def detect_candidate_environments(self) -> list[dict[str, str]]:
        """Find unused local venvs under the active project/workspace root."""
        workspace = self._require_workspace()
        registered = {
            item.path.resolve()
            for item in await self._repository.list_by_workspace(workspace.id)
        }
        candidates: list[dict[str, str]] = []
        for path in self._fs.discover_candidates(workspace.path):
            if path.resolve() in registered:
                continue
            candidates.append(
                {
                    "name": path.name.lstrip(".") or path.name,
                    "path": str(path.resolve()),
                },
            )
        return candidates

    async def get_environment(self, environment_id: UUID) -> Environment:
        workspace = self._require_workspace()
        environment = await self._repository.get(environment_id)
        if environment is None or environment.workspace_id != workspace.id:
            raise EnvironmentValidationError(
                "Environment not found in the active workspace",
            )
        if not environment.path.is_dir():
            raise EnvironmentValidationError(
                f"Environment directory is missing: '{environment.path}'",
            )
        return await self._enrich(environment)

    async def activate_environment(self, environment_id: UUID) -> Environment:
        workspace = self._require_workspace()
        environment = await self._repository.get(environment_id)
        if environment is None or environment.workspace_id != workspace.id:
            raise EnvironmentValidationError(
                "Environment not found in the active workspace",
            )
        await self._activate(environment)
        refreshed = await self._repository.get(environment_id)
        assert refreshed is not None
        return await self._enrich(refreshed)

    async def clone_environment(
        self,
        environment_id: UUID,
        name: str,
    ) -> Environment:
        workspace = self._require_workspace()
        source = await self._repository.get(environment_id)
        if source is None or source.workspace_id != workspace.id:
            raise EnvironmentValidationError(
                "Source environment not found in the active workspace",
            )
        if not source.path.is_dir():
            raise EnvironmentValidationError(
                f"Source environment directory is missing: '{source.path}'",
            )

        cleaned = self._fs.validate_name(name)
        if self._fs.find_existing_environment_root(workspace.path, cleaned) is not None:
            raise EnvironmentValidationError(
                f"An environment named '{cleaned}' already exists",
            )
        target_root = self._fs.environment_root_for_name(workspace.path, cleaned)

        # Create empty venv using the same Python major.minor when possible.
        base_python = source.python_executable
        self._python.create_venv(base_python, target_root)

        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                suffix="-requirements.txt",
                delete=False,
                encoding="utf-8",
            ) as handle:
                requirements = Path(handle.name)
            try:
                self._python.freeze_requirements(source.python_executable, requirements)
                target_exec = self._python.resolve_executables(target_root)
                self._python.install_requirements(target_exec.python, requirements)
            finally:
                requirements.unlink(missing_ok=True)

            executables = self._python.resolve_executables(target_root)
            python_version = self._python.get_python_version(executables.python)
            manifest = self._fs.create_manifest(
                name=cleaned,
                python_version=python_version,
                python_executable=executables.python,
                pip_executable=executables.pip,
                robot_executable=executables.robot,
                path=target_root,
                active=False,
            )
            self._fs.write_manifest(target_root, manifest)
            cloned = self._from_manifest(workspace.id, manifest)
            await self._repository.create(cloned)
            await self._event_bus.publish(
                EnvironmentCloned(
                    workspace_id=workspace.id,
                    source_environment_id=source.id,
                    environment_id=cloned.id,
                ),
            )
            return await self._enrich(cloned)
        except Exception:
            if target_root.exists():
                self._fs.delete_directory(target_root)
            raise

    async def delete_environment(
        self,
        environment_id: UUID,
        *,
        delete_files: bool = False,
    ) -> None:
        workspace = self._require_workspace()
        environment = await self._repository.get(environment_id)
        if environment is None or environment.workspace_id != workspace.id:
            raise EnvironmentValidationError(
                "Environment not found in the active workspace",
            )
        if environment.is_active or (
            self._context.environment_id is not None
            and self._context.environment_id == environment.id
        ):
            if self._has_python(environment):
                raise EnvironmentValidationError(
                    "Cannot delete the active environment. Activate another environment first.",
                )
            # Broken/missing active env — allow cleanup so the user can recover.
            await self._repository.clear_active(workspace.id)
            if self._context.environment_id == environment.id:
                await self._context.clear_active_environment()

        await self._repository.delete(environment_id)
        if delete_files:
            self._fs.delete_directory(environment.path)
        elif self._fs.has_manifest(environment.path):
            # Keep folder but clear active flag if present.
            try:
                manifest = self._fs.load_manifest(environment.path)
                if manifest.active:
                    updated = self._fs.create_manifest(
                        name=manifest.name,
                        python_version=manifest.python_version,
                        python_executable=manifest.python_executable,
                        pip_executable=manifest.pip_executable,
                        robot_executable=manifest.robot_executable,
                        path=manifest.path,
                        active=False,
                        environment_id=manifest.id,
                        created_at=manifest.created_at,
                    )
                    self._fs.write_manifest(environment.path, updated)
            except EnvironmentValidationError:
                pass

        await self._event_bus.publish(
            EnvironmentDeleted(
                workspace_id=workspace.id,
                environment_id=environment_id,
            ),
        )

    async def _activate(self, environment: Environment) -> None:
        workspace = self._require_workspace()
        await self._repository.set_active(workspace.id, environment.id)

        # Persist active flags into environment.json files.
        for item in await self._repository.list_by_workspace(workspace.id):
            if not self._fs.has_manifest(item.path):
                continue
            try:
                manifest = self._fs.load_manifest(item.path)
            except EnvironmentValidationError:
                continue
            desired = item.id == environment.id
            if manifest.active == desired:
                continue
            updated = self._fs.create_manifest(
                name=manifest.name,
                python_version=manifest.python_version,
                python_executable=manifest.python_executable,
                pip_executable=manifest.pip_executable,
                robot_executable=manifest.robot_executable,
                path=manifest.path,
                active=desired,
                environment_id=manifest.id,
                created_at=manifest.created_at,
            )
            self._fs.write_manifest(item.path, updated)

        active = environment.model_copy(update={"is_active": True})
        await self._context.set_active_environment(active)

        updated_workspace = workspace.model_copy(
            update={
                "settings": WorkspaceSettings(
                    default_environment_id=environment.id,
                    robot_options=list(workspace.settings.robot_options),
                ),
            },
        )
        self._context.replace_workspace(updated_workspace)

        await self._event_bus.publish(
            EnvironmentActivated(
                workspace_id=workspace.id,
                environment_id=environment.id,
            ),
        )

    async def _hydrate_from_disk(
        self,
        workspace_id: UUID,
        workspace_path: Path,
    ) -> list[Environment]:
        environments = await self._repository.list_by_workspace(workspace_id)
        if environments:
            # Keep rows even when the folder was deleted so the UI can show
            # "active but missing" instead of a healthy-looking ghost state.
            # Ghosts from a previous project life at this path are cleared on
            # WorkspaceOpened via purge_missing_environments.
            return environments

        hydrated: list[Environment] = []
        for env_root in self._fs.discover(workspace_path):
            try:
                executables = self._python.resolve_executables(env_root)
            except EnvironmentValidationError:
                continue

            if self._fs.has_manifest(env_root):
                try:
                    manifest = self._fs.load_manifest(env_root)
                except EnvironmentValidationError:
                    continue
            else:
                manifest = self._fs.create_manifest(
                    name=env_root.name,
                    python_version=self._python.get_python_version(executables.python),
                    python_executable=executables.python,
                    pip_executable=executables.pip,
                    robot_executable=executables.robot,
                    path=env_root,
                    active=False,
                )
                self._fs.write_manifest(env_root, manifest)

            environment = self._from_manifest(workspace_id, manifest)
            await self._repository.create(environment)
            hydrated.append(environment)
        return hydrated

    async def _sync_active_context(self, environments: list[Environment]) -> None:
        active = next((item for item in environments if item.is_active), None)
        if active is None:
            if self._context.environment is not None:
                await self._context.clear_active_environment()
            return
        if (
            self._context.environment_id != active.id
            or self._context.environment is None
        ):
            await self._context.set_active_environment(active)

    async def _enrich(self, environment: Environment) -> Environment:
        if not self._has_python(environment):
            return environment.model_copy(update={"available": False})
        python = environment.python_executable
        if not python.is_file():
            try:
                python = self._python.resolve_executables(environment.path).python
            except EnvironmentValidationError:
                return environment.model_copy(update={"available": False})
        info = self._python.inspect(python)
        robot_exe = environment.robot_executable
        if info.robot_version and (robot_exe is None or not Path(robot_exe).is_file()):
            try:
                robot_exe = self._python.resolve_executables(environment.path).robot
            except EnvironmentValidationError:
                robot_exe = environment.robot_executable
        enriched = environment.model_copy(
            update={
                "python_version": info.python_version,
                "robot_version": info.robot_version,
                "package_count": info.package_count,
                "platform": info.platform,
                "architecture": info.architecture,
                "robot_executable": robot_exe,
                "available": True,
            },
        )
        # Persist upgraded major.minor → major.minor.micro (and related fields).
        if enriched.python_version != environment.python_version:
            await self._repository.update(enriched)
            if self._fs.has_manifest(environment.path):
                try:
                    manifest = self._fs.load_manifest(environment.path)
                    updated = self._fs.create_manifest(
                        name=manifest.name,
                        python_version=enriched.python_version,
                        python_executable=manifest.python_executable,
                        pip_executable=manifest.pip_executable,
                        robot_executable=enriched.robot_executable
                        or manifest.robot_executable,
                        path=manifest.path,
                        active=manifest.active,
                        environment_id=manifest.id,
                        created_at=manifest.created_at,
                    )
                    self._fs.write_manifest(environment.path, updated)
                except EnvironmentValidationError:
                    pass
        return enriched

    @staticmethod
    def _has_python(environment: Environment) -> bool:
        if environment.python_executable.is_file():
            return True
        if (environment.path / "bin" / "python").is_file():
            return True
        if (environment.path / "Scripts" / "python.exe").is_file():
            return True
        return False

    @staticmethod
    def _from_manifest(workspace_id: UUID, manifest) -> Environment:
        created_at = (
            manifest.created_at
            if manifest.created_at.tzinfo
            else manifest.created_at.replace(tzinfo=UTC)
        )
        return Environment(
            id=manifest.id,
            workspace_id=workspace_id,
            name=manifest.name,
            path=Path(manifest.path).resolve(),
            python_version=manifest.python_version,
            python_executable=Path(manifest.python_executable),
            pip_executable=Path(manifest.pip_executable),
            robot_executable=(
                Path(manifest.robot_executable) if manifest.robot_executable else None
            ),
            created_at=created_at,
            is_active=manifest.active,
        )

    @staticmethod
    def _sort(environments: list[Environment], sort: SortKey) -> list[Environment]:
        key = (sort or "active").lower()
        if key == "name":
            return sorted(environments, key=lambda item: item.name.lower())
        if key == "created_at":
            return sorted(environments, key=lambda item: item.created_at, reverse=True)
        # Default: active first, then name
        return sorted(
            environments,
            key=lambda item: (0 if item.is_active else 1, item.name.lower()),
        )
