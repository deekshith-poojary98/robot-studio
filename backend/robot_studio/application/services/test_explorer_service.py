"""Test Explorer — discover suites/tests/tasks/tags and run via ExecutionService."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID

from robot_studio.application.services.execution_service import (
    ExecutionService,
    ExecutionValidationError,
)
from robot_studio.application.services.project_service import ProjectService
from robot_studio.application.services.settings_service import SettingsService
from robot_studio.application.services.workspace_context import WorkspaceContext
from robot_studio.core.config import settings as env_settings
from robot_studio.core.events import (
    EventBus,
    ExecutionFailed,
    ExecutionFinished,
    ExecutionStarted,
    IndexUpdated,
    WorkspaceOpened,
)
from robot_studio.domain.interfaces.indexing import SymbolKind
from robot_studio.domain.models import ExecutionRun
from robot_studio.infrastructure.execution.output_stats import (
    list_failed_tests,
    parse_test_results,
)
from robot_studio.infrastructure.indexing.sqlite_store import SqliteIndexStore
from robot_studio.infrastructure.language.robot_parsing_worker import document_symbols


class TestExplorerValidationError(Exception):
    """Raised when Test Explorer cannot discover or run tests."""

    def __init__(
        self,
        message: str,
        *,
        code: str | None = None,
        count: int | None = None,
        threshold: int | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.count = count
        self.threshold = threshold


@dataclass
class TestNode:
    id: str
    kind: str
    name: str
    path: str | None = None
    line: int | None = None
    project_id: str | None = None
    status: str = "not_run"
    tags: list[str] = field(default_factory=list)
    detail: str = ""
    children: list[TestNode] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "kind": self.kind,
            "name": self.name,
            "path": self.path,
            "line": self.line,
            "project_id": self.project_id,
            "status": self.status,
            "tags": list(self.tags),
            "detail": self.detail,
            "children": [child.to_dict() for child in self.children],
        }


@dataclass
class TestExplorerService:
    context: WorkspaceContext
    event_bus: EventBus
    store: SqliteIndexStore
    project_service: ProjectService
    execution_service: ExecutionService
    settings_service: SettingsService | None = None
    _tree: TestNode | None = field(default=None, init=False)
    _statuses: dict[str, str] = field(default_factory=dict, init=False)
    _running_keys: set[str] = field(default_factory=set, init=False)
    _subscribed: bool = field(default=False, init=False)

    def start(self) -> None:
        if self._subscribed:
            return
        self.event_bus.subscribe(WorkspaceOpened, self._on_workspace_opened)
        self.event_bus.subscribe(IndexUpdated, self._on_index_updated)
        self.event_bus.subscribe(ExecutionStarted, self._on_execution_started)
        self.event_bus.subscribe(ExecutionFinished, self._on_execution_finished)
        self.event_bus.subscribe(ExecutionFailed, self._on_execution_failed)
        self._subscribed = True

    def _require_workspace(self):
        workspace = self.context.workspace
        if workspace is None:
            raise TestExplorerValidationError("Open a workspace before using Test Explorer")
        return workspace

    async def _on_workspace_opened(self, event: WorkspaceOpened) -> None:
        _ = event
        self._tree = None
        self._statuses.clear()
        self._running_keys.clear()

    async def _on_index_updated(self, event: IndexUpdated) -> None:
        _ = event
        # Incremental: drop cache so next tree read rebuilds from IndexStore.
        self._tree = None

    async def _on_execution_started(self, event: ExecutionStarted) -> None:
        _ = event
        self._running_keys = {"*"}

    async def _on_execution_finished(self, event: ExecutionFinished) -> None:
        await self._apply_run_results(event.run_id)

    async def _on_execution_failed(self, event: ExecutionFailed) -> None:
        self._running_keys.clear()
        _ = event

    async def _apply_run_results(self, run_id: UUID) -> None:
        self._running_keys.clear()
        run = await self.execution_service.repository.get(run_id)
        if run is None or run.output_xml is None:
            self._tree = None
            return
        for item in parse_test_results(run.output_xml):
            name = str(item.get("name") or "")
            source = str(item.get("source") or "")
            status = str(item.get("status") or "NOT RUN").lower()
            if status == "pass":
                mapped = "pass"
            elif status == "fail":
                mapped = "fail"
            elif status == "skip":
                mapped = "skip"
            else:
                mapped = "not_run"
            if source and name:
                self._statuses[self._case_key(source, name)] = mapped
            if name:
                self._statuses[f"name:{name}"] = mapped
        self._tree = None

    @staticmethod
    def _case_key(path: str, name: str) -> str:
        return f"{Path(path).resolve()}::{name}"

    async def get_tree(self, *, query: str | None = None, lazy: bool = True) -> TestNode:
        workspace = self._require_workspace()
        # Filtering needs test names — build eagerly.
        use_lazy = lazy and not (query and query.strip())
        cache_key_ok = self._tree is not None and getattr(self, "_tree_lazy", None) == use_lazy
        if not cache_key_ok:
            self._tree = await self._build_tree(workspace, lazy=use_lazy)
            self._tree_lazy = use_lazy
        tree = self._tree
        if query and query.strip():
            return self._filter_tree(tree, query.strip().lower())
        return tree

    def _path_allowed(self, target: Path) -> bool:
        roots: list[Path] = []
        workspace = self.context.workspace
        if workspace is not None:
            roots.append(Path(workspace.path).resolve())
        project = self.context.project
        if project is not None:
            roots.append(Path(project.path).resolve())
        for root in roots:
            try:
                target.relative_to(root)
                return True
            except ValueError:
                continue
        return False

    async def get_file(self, path: str) -> list[TestNode]:
        self._require_workspace()
        target = Path(path).expanduser().resolve()
        if not target.is_file():
            raise TestExplorerValidationError(f"File not found: '{target}'")
        if not self._path_allowed(target):
            raise TestExplorerValidationError(
                "Path is outside the active project or workspace",
            )

        # Prefer live parser (robot.api) for per-file accuracy; fall back to index.
        symbols = await self._parse_file_symbols(target)
        if not symbols:
            symbols = await self.store.symbols_for_file(target)
        return self._nodes_from_file_symbols(target, symbols)

    async def count_tests(
        self,
        *,
        tag: str | None = None,
        project_wide: bool = False,
    ) -> int:
        """Estimate tests for confirmation dialogs (tag / run-all)."""
        project = self.context.project
        if project is None:
            raise TestExplorerValidationError("Open a project first")
        if tag and tag.strip():
            needle = tag.strip().lower()
            tags = await self.store.search_symbols(
                needle,
                project_id=project.id,
                kind=SymbolKind.TAG,
                limit=5000,
            )
            # Each tag symbol is one attachment; count unique test names when possible.
            names = {
                str(t.get("detail") or "").split(":", 1)[-1]
                for t in tags
                if str(t.get("name") or "").lower() == needle
                and str(t.get("detail") or "").startswith("test:")
            }
            if names:
                return len(names)
            # Force/Default tags apply suite-wide — fall back to test_case count.
            cases = await self.store.search_symbols(
                "",
                project_id=project.id,
                kind=SymbolKind.TEST_CASE,
                limit=10000,
            )
            return len(cases) if any(
                str(t.get("name") or "").lower() == needle for t in tags
            ) else max(len(tags), 0)
        if project_wide:
            cases = await self.store.search_symbols(
                "",
                project_id=project.id,
                kind=SymbolKind.TEST_CASE,
                limit=10000,
            )
            return len(cases)
        return 0

    async def refresh(self) -> TestNode:
        self._require_workspace()
        self._tree = None
        return await self.get_tree()

    async def run_test(self, *, file: str, name: str) -> ExecutionRun:
        self._require_workspace()
        if not name.strip():
            raise TestExplorerValidationError("Test name is required")
        suite = str(Path(file).expanduser().resolve())
        self._running_keys = {self._case_key(suite, name)}
        return await self.execution_service.run_with_options(
            suite=suite,
            robot_args=["--test", name.strip()],
            run_label=f"{Path(suite).name} :: {name.strip()}",
        )

    async def run_suite(self, *, file: str | None = None, confirm: bool = False) -> ExecutionRun:
        self._require_workspace()
        if file:
            suite = str(Path(file).expanduser().resolve())
            label = f"Suite: {Path(suite).name}"
            return await self.execution_service.run_with_options(
                suite=suite,
                run_label=label,
            )
        await self._assert_large_run_allowed(confirm=confirm, tag=None, project_wide=True)
        return await self.execution_service.run_project()

    async def run_tag(self, *, tag: str, confirm: bool = False) -> ExecutionRun:
        self._require_workspace()
        cleaned = tag.strip()
        if not cleaned:
            raise TestExplorerValidationError("Tag is required")
        project = self.context.project
        if project is None:
            raise TestExplorerValidationError("Open a project before running by tag")
        await self._assert_large_run_allowed(
            confirm=confirm,
            tag=cleaned,
            project_wide=True,
        )
        return await self.execution_service.run_with_options(
            suite=str(project.path),
            robot_args=["--include", cleaned],
            run_label=f"Tag: {cleaned}",
        )

    async def _assert_large_run_allowed(
        self,
        *,
        confirm: bool,
        tag: str | None,
        project_wide: bool,
    ) -> None:
        if confirm:
            return
        if self.settings_service is not None:
            threshold = max(
                1,
                int(self.settings_service.get().execution.large_run_threshold),
            )
        else:
            threshold = max(1, int(env_settings.large_run_threshold))
        count = await self.count_tests(tag=tag, project_wide=project_wide)
        wildcard = bool(
            tag
            and (
                "*" in tag
                or "?" in tag
                or " OR " in tag.upper()
                or " AND " in tag.upper()
                or " NOT " in tag.upper()
            )
        )
        if count <= threshold and not wildcard:
            return
        label = f'tag "{tag}"' if tag else "the project"
        raise TestExplorerValidationError(
            f"This run would execute about {count} tests for {label} "
            f"(threshold {threshold}). Confirm to proceed.",
            code="large_run_confirmation_required",
            count=count,
            threshold=threshold,
        )

    async def ensure_large_run_allowed(
        self,
        *,
        confirm: bool,
        tag: str | None = None,
        project_wide: bool = True,
    ) -> None:
        """Public wrapper used by execution/run-project gateway."""
        await self._assert_large_run_allowed(
            confirm=confirm,
            tag=tag,
            project_wide=project_wide,
        )

    async def run_failed(self) -> ExecutionRun:
        self._require_workspace()
        project = self.context.project
        if project is None:
            raise TestExplorerValidationError("Open a project before re-running failed tests")

        output_xml: Path | None = None
        current = await self.execution_service.get_status()
        candidates: list[ExecutionRun] = []
        if current is not None:
            candidates.append(current)
        candidates.extend(await self.execution_service.list_history(limit=20))

        for run in candidates:
            if run.output_xml is not None and Path(run.output_xml).is_file():
                output_xml = Path(run.output_xml)
                break
            if run.output_dir is not None:
                candidate = Path(run.output_dir) / "output.xml"
                if candidate.is_file():
                    output_xml = candidate
                    break

        if output_xml is None:
            raise TestExplorerValidationError("No previous run with output.xml to re-run")
        failed = list_failed_tests(output_xml)
        if not failed:
            raise TestExplorerValidationError("Last run has no failed tests")
        return await self.execution_service.run_with_options(
            suite=str(project.path),
            robot_args=["--rerunfailed", str(output_xml)],
            run_label=f"Failed ({len(failed)})",
        )

    async def run_selected(self, *, tests: list[dict]) -> ExecutionRun:
        self._require_workspace()
        if not tests:
            raise TestExplorerValidationError("Select at least one test")
        # Group by suite file; Robot allows multiple --test for one suite.
        by_file: dict[str, list[str]] = {}
        for item in tests:
            path = str(Path(str(item.get("file") or "")).expanduser().resolve())
            name = str(item.get("name") or "").strip()
            if not path or not name:
                continue
            by_file.setdefault(path, []).append(name)
        if not by_file:
            raise TestExplorerValidationError("No valid tests in selection")
        if len(by_file) == 1:
            suite, names = next(iter(by_file.items()))
            args: list[str] = []
            for name in names:
                args.extend(["--test", name])
            label = (
                f"{Path(suite).name} :: {names[0]}"
                if len(names) == 1
                else f"{Path(suite).name} :: {len(names)} tests"
            )
            return await self.execution_service.run_with_options(
                suite=suite,
                robot_args=args,
                run_label=label,
            )
        # Multiple files: run whole project with name filters (OR).
        project = self.context.project
        if project is None:
            raise TestExplorerValidationError("Open a project before running selected tests")
        args = []
        for names in by_file.values():
            for name in names:
                args.extend(["--test", name])
        return await self.execution_service.run_with_options(
            suite=str(project.path),
            robot_args=args,
            run_label=f"Selected ({sum(len(v) for v in by_file.values())})",
        )

    async def _parse_file_symbols(self, path: Path) -> list[dict]:
        try:
            content = path.read_text(encoding="utf-8")
        except OSError:
            return []
        try:
            raw = document_symbols(content, str(path))
        except Exception:
            return []
        return [
            {
                **item,
                "file_path": str(path),
                "kind": item.get("kind"),
            }
            for item in raw
        ]

    async def _build_tree(self, workspace, *, lazy: bool = True) -> TestNode:
        projects = await self.project_service.list_projects()
        project_nodes: list[TestNode] = []
        for project in projects:
            suites = await self.store.search_symbols(
                "",
                project_id=project.id,
                kind=SymbolKind.TEST_SUITE,
                limit=10000,
            )
            # Deduplicate by file_path.
            by_path: dict[str, dict] = {}
            for suite in suites:
                file_path = str(suite.get("file_path") or "")
                if not file_path:
                    continue
                by_path[file_path] = suite

            # Also discover .robot files under project if index empty.
            if not by_path:
                for robot_file in sorted(project.path.rglob("*.robot")):
                    by_path[str(robot_file)] = {
                        "name": robot_file.stem,
                        "file_path": str(robot_file),
                        "line": 1,
                    }

            suite_nodes: list[TestNode] = []
            for file_path, suite in sorted(by_path.items()):
                children: list[TestNode] = []
                detail = ""
                if lazy:
                    # Children loaded on expand via GET /tests/file.
                    detail = "expand"
                else:
                    symbols = await self.store.symbols_for_file(Path(file_path))
                    if not symbols:
                        symbols = await self._parse_file_symbols(Path(file_path))
                    children = self._nodes_from_file_symbols(
                        Path(file_path),
                        symbols,
                        project_id=str(project.id),
                    )
                suite_status = self._rollup_status(children) if children else "not_run"
                suite_nodes.append(
                    TestNode(
                        id=f"suite:{file_path}",
                        kind="suite",
                        name=str(suite.get("name") or Path(file_path).stem),
                        path=file_path,
                        line=int(suite.get("line") or 1),
                        project_id=str(project.id),
                        status=suite_status,
                        detail=detail,
                        children=children,
                    ),
                )

            project_nodes.append(
                TestNode(
                    id=f"project:{project.id}",
                    kind="project",
                    name=project.name,
                    path=str(project.path),
                    project_id=str(project.id),
                    status=self._rollup_status(suite_nodes),
                    children=suite_nodes,
                ),
            )

        return TestNode(
            id=f"workspace:{workspace.id}",
            kind="workspace",
            name=workspace.name,
            path=str(workspace.path),
            status=self._rollup_status(project_nodes),
            children=project_nodes,
        )

    def _nodes_from_file_symbols(
        self,
        path: Path,
        symbols: list[dict],
        *,
        project_id: str | None = None,
    ) -> list[TestNode]:
        path_str = str(path.resolve()) if path.exists() else str(path)
        tags_by_test: dict[str, list[str]] = {}
        suite_tags: list[str] = []
        setups: list[TestNode] = []
        cases: list[TestNode] = []

        for symbol in symbols:
            kind = str(symbol.get("kind") or "")
            name = str(symbol.get("name") or "")
            detail = str(symbol.get("detail") or "")
            line = int(symbol.get("line") or 1)
            if kind == "tag":
                if detail.startswith("test:"):
                    test_name = detail.split(":", 1)[1]
                    tags_by_test.setdefault(test_name, []).append(name)
                elif detail in {"Force Tags", "Default Tags"}:
                    suite_tags.append(name)
            elif kind == "setting":
                if detail in {
                    "Suite Setup",
                    "Suite Teardown",
                    "Test Setup",
                    "Test Teardown",
                } or detail.startswith("Setup:") or detail.startswith("Teardown:"):
                    setups.append(
                        TestNode(
                            id=f"setting:{path_str}:{detail}:{name}:{line}",
                            kind="setup" if "Setup" in detail else "teardown",
                            name=f"{detail}: {name}" if ":" not in detail else f"{detail.split(':', 1)[0]}: {name}",
                            path=path_str,
                            line=line,
                            project_id=project_id,
                            detail=detail,
                            status="not_run",
                        ),
                    )

        for symbol in symbols:
            kind = str(symbol.get("kind") or "")
            if kind != "test_case":
                continue
            name = str(symbol.get("name") or "")
            detail = str(symbol.get("detail") or "")
            line = int(symbol.get("line") or 1)
            is_task = detail.startswith("tasks")
            tags = list(tags_by_test.get(name, []))
            if "|tags:" in detail:
                tags.extend(
                    tag
                    for tag in detail.split("|tags:", 1)[1].split(",")
                    if tag
                )
            tags = list(dict.fromkeys(tags + suite_tags))
            key = self._case_key(path_str, name)
            status = self._status_for(key, name)
            cases.append(
                TestNode(
                    id=f"{'task' if is_task else 'test'}:{path_str}:{name}",
                    kind="task" if is_task else "test",
                    name=name,
                    path=path_str,
                    line=line,
                    project_id=project_id,
                    status=status,
                    tags=tags,
                    detail=detail,
                ),
            )

        return [*setups, *cases]

    def _status_for(self, key: str, name: str) -> str:
        if "*" in self._running_keys or key in self._running_keys:
            return "running"
        return self._statuses.get(key) or self._statuses.get(f"name:{name}") or "not_run"

    @staticmethod
    def _rollup_status(nodes: list[TestNode]) -> str:
        if not nodes:
            return "not_run"
        statuses = {node.status for node in nodes}
        if "running" in statuses:
            return "running"
        if "fail" in statuses:
            return "fail"
        if statuses == {"pass"} or (statuses <= {"pass", "skip", "not_run"} and "pass" in statuses and "fail" not in statuses and "not_run" not in statuses):
            if statuses <= {"pass", "skip"}:
                return "pass"
        if statuses <= {"skip", "not_run"} and "skip" in statuses:
            return "skip"
        if "pass" in statuses and "not_run" not in statuses and "fail" not in statuses:
            return "pass"
        return "not_run"

    def _filter_tree(self, node: TestNode, query: str) -> TestNode:
        filtered_children = []
        for child in node.children:
            filtered = self._filter_tree(child, query)
            if filtered.children or self._node_matches(filtered, query):
                filtered_children.append(filtered)
        return TestNode(
            id=node.id,
            kind=node.kind,
            name=node.name,
            path=node.path,
            line=node.line,
            project_id=node.project_id,
            status=node.status,
            tags=list(node.tags),
            detail=node.detail,
            children=filtered_children,
        )

    @staticmethod
    def _node_matches(node: TestNode, query: str) -> bool:
        haystacks = [
            node.name.lower(),
            (node.path or "").lower(),
            node.kind.lower(),
            node.detail.lower(),
            *[tag.lower() for tag in node.tags],
        ]
        return any(query in item for item in haystacks)
