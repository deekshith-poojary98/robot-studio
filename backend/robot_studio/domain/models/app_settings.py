"""Typed application preferences — immutable semantic models.

Owned exclusively by SettingsService. Consumers must not read settings.json.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field, replace
from typing import Any

SETTINGS_SCHEMA_VERSION = 1

_DEFAULT_SEARCH_EXTENSIONS = (
    ".robot",
    ".resource",
    ".py",
    ".yaml",
    ".yml",
    ".txt",
    ".md",
    ".json",
    ".tsv",
    ".csv",
)

_DEFAULT_IGNORE_PATTERNS = (
    ".git",
    ".venv",
    "venv",
    "node_modules",
    "__pycache__",
    ".robotstudio",
    ".DS_Store",
)


@dataclass(frozen=True)
class EditorSettings:
    auto_save: bool = False
    save_before_run: bool = True
    tab_width: int = 4
    insert_spaces: bool = True
    word_wrap: bool = True
    font_size: int = 13
    font_family: str = "Menlo"

    def to_api(self) -> dict[str, Any]:
        return asdict(self)

    @staticmethod
    def from_api(raw: dict[str, Any] | None) -> EditorSettings:
        raw = raw or {}
        return EditorSettings(
            auto_save=bool(raw.get("auto_save", False)),
            save_before_run=bool(raw.get("save_before_run", True)),
            tab_width=max(1, min(16, int(raw.get("tab_width", 4) or 4))),
            insert_spaces=bool(raw.get("insert_spaces", True)),
            word_wrap=bool(raw.get("word_wrap", True)),
            font_size=max(9, min(32, int(raw.get("font_size", 13) or 13))),
            font_family=str(raw.get("font_family") or "Menlo").strip() or "Menlo",
        )


@dataclass(frozen=True)
class ExecutionSettings:
    large_run_threshold: int = 100
    reveal_execution_on_run: bool = True
    auto_open_report_on_failure: bool = False
    stop_confirmation: bool = True

    def to_api(self) -> dict[str, Any]:
        return asdict(self)

    @staticmethod
    def from_api(raw: dict[str, Any] | None) -> ExecutionSettings:
        raw = raw or {}
        return ExecutionSettings(
            large_run_threshold=max(
                1,
                min(10_000, int(raw.get("large_run_threshold", 100) or 100)),
            ),
            reveal_execution_on_run=bool(raw.get("reveal_execution_on_run", True)),
            auto_open_report_on_failure=bool(
                raw.get("auto_open_report_on_failure", False),
            ),
            stop_confirmation=bool(raw.get("stop_confirmation", True)),
        )


@dataclass(frozen=True)
class SearchSettings:
    content_search_extensions: tuple[str, ...] = _DEFAULT_SEARCH_EXTENSIONS
    ignore_patterns: tuple[str, ...] = _DEFAULT_IGNORE_PATTERNS

    def to_api(self) -> dict[str, Any]:
        return {
            "content_search_extensions": list(self.content_search_extensions),
            "ignore_patterns": list(self.ignore_patterns),
        }

    @staticmethod
    def from_api(raw: dict[str, Any] | None) -> SearchSettings:
        raw = raw or {}
        return SearchSettings(
            content_search_extensions=_normalize_extensions(
                raw.get("content_search_extensions"),
                default=_DEFAULT_SEARCH_EXTENSIONS,
            ),
            ignore_patterns=_normalize_patterns(
                raw.get("ignore_patterns"),
                default=_DEFAULT_IGNORE_PATTERNS,
            ),
        )

    def extensions_csv(self) -> str:
        return ",".join(self.content_search_extensions)


@dataclass(frozen=True)
class AppearanceSettings:
    """Theme: dark | light | system. Accent: curated accent colour id."""

    theme: str = "dark"
    accent: str = "teal"
    restore_last_project: bool = True

    def to_api(self) -> dict[str, Any]:
        return asdict(self)

    @staticmethod
    def from_api(raw: dict[str, Any] | None) -> AppearanceSettings:
        raw = raw or {}
        theme = str(raw.get("theme") or "dark").strip().lower()
        if theme not in {"dark", "light", "system"}:
            theme = "dark"
        accent = str(raw.get("accent") or "teal").strip().lower()
        if accent not in {"teal", "blue", "green", "amber", "rose", "slate"}:
            accent = "teal"
        return AppearanceSettings(
            theme=theme,
            accent=accent,
            restore_last_project=bool(raw.get("restore_last_project", True)),
        )


@dataclass(frozen=True)
class AppSettings:
    """Complete preference snapshot (immutable)."""

    version: int = SETTINGS_SCHEMA_VERSION
    editor: EditorSettings = field(default_factory=EditorSettings)
    execution: ExecutionSettings = field(default_factory=ExecutionSettings)
    search: SearchSettings = field(default_factory=SearchSettings)
    appearance: AppearanceSettings = field(default_factory=AppearanceSettings)

    def to_api(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "editor": self.editor.to_api(),
            "execution": self.execution.to_api(),
            "search": self.search.to_api(),
            "appearance": self.appearance.to_api(),
        }

    def merge_patch(self, patch: dict[str, Any]) -> AppSettings:
        """Return a new snapshot with non-null sections from *patch* applied."""
        editor = self.editor
        execution = self.execution
        search = self.search
        appearance = self.appearance
        if isinstance(patch.get("editor"), dict):
            merged = {**self.editor.to_api(), **patch["editor"]}
            editor = EditorSettings.from_api(merged)
        if isinstance(patch.get("execution"), dict):
            merged = {**self.execution.to_api(), **patch["execution"]}
            execution = ExecutionSettings.from_api(merged)
        if isinstance(patch.get("search"), dict):
            merged = {**self.search.to_api(), **patch["search"]}
            search = SearchSettings.from_api(merged)
        if isinstance(patch.get("appearance"), dict):
            merged = {**self.appearance.to_api(), **patch["appearance"]}
            appearance = AppearanceSettings.from_api(merged)
        return replace(
            self,
            version=SETTINGS_SCHEMA_VERSION,
            editor=editor,
            execution=execution,
            search=search,
            appearance=appearance,
        )

    @staticmethod
    def from_api(raw: dict[str, Any] | None) -> AppSettings:
        raw = raw or {}
        return AppSettings(
            version=int(raw.get("version") or SETTINGS_SCHEMA_VERSION),
            editor=EditorSettings.from_api(
                raw.get("editor") if isinstance(raw.get("editor"), dict) else {},
            ),
            execution=ExecutionSettings.from_api(
                raw.get("execution") if isinstance(raw.get("execution"), dict) else {},
            ),
            search=SearchSettings.from_api(
                raw.get("search") if isinstance(raw.get("search"), dict) else {},
            ),
            appearance=AppearanceSettings.from_api(
                raw.get("appearance")
                if isinstance(raw.get("appearance"), dict)
                else {},
            ),
        )


def _normalize_extensions(value: Any, *, default: tuple[str, ...]) -> tuple[str, ...]:
    items: list[str]
    if value is None:
        items = list(default)
    elif isinstance(value, str):
        items = [part.strip() for part in value.split(",") if part.strip()]
    elif isinstance(value, (list, tuple)):
        items = [str(part).strip() for part in value if str(part).strip()]
    else:
        items = list(default)
    out: list[str] = []
    seen: set[str] = set()
    for item in items:
        cleaned = item.lower()
        if not cleaned.startswith("."):
            cleaned = f".{cleaned}"
        if cleaned in seen:
            continue
        seen.add(cleaned)
        out.append(cleaned)
    return tuple(out) if out else default


def _normalize_patterns(value: Any, *, default: tuple[str, ...]) -> tuple[str, ...]:
    if value is None:
        return default
    if isinstance(value, str):
        items = [part.strip() for part in value.split(",") if part.strip()]
    elif isinstance(value, (list, tuple)):
        items = [str(part).strip() for part in value if str(part).strip()]
    else:
        return default
    out: list[str] = []
    seen: set[str] = set()
    for item in items:
        key = item.casefold()
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return tuple(out) if out else default


def migrate_settings_dict(raw: dict[str, Any]) -> dict[str, Any]:
    """Upgrade on-disk JSON to the current schema version."""
    version = int(raw.get("version") or 0)
    data = dict(raw)

    # v0 → v1: flatten legacy env-style keys into sections.
    if version < 1:
        editor = dict(data.get("editor") or {}) if isinstance(data.get("editor"), dict) else {}
        execution = (
            dict(data.get("execution") or {})
            if isinstance(data.get("execution"), dict)
            else {}
        )
        search = dict(data.get("search") or {}) if isinstance(data.get("search"), dict) else {}
        appearance = (
            dict(data.get("appearance") or {})
            if isinstance(data.get("appearance"), dict)
            else {}
        )

        if "large_run_threshold" in data and "large_run_threshold" not in execution:
            execution["large_run_threshold"] = data["large_run_threshold"]
        if "content_search_extensions" in data and "content_search_extensions" not in search:
            search["content_search_extensions"] = data["content_search_extensions"]
        if "word_wrap" in data and "word_wrap" not in editor:
            editor["word_wrap"] = data["word_wrap"]
        if "theme" in data and "theme" not in appearance:
            appearance["theme"] = data["theme"]

        data = {
            "version": 1,
            "editor": editor,
            "execution": execution,
            "search": search,
            "appearance": appearance,
        }
        version = 1

    data["version"] = SETTINGS_SCHEMA_VERSION
    # Round-trip through models to clamp / normalize.
    return AppSettings.from_api(data).to_api()
