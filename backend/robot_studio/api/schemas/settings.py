"""HTTP schemas for application preferences."""

from __future__ import annotations

from pydantic import BaseModel, Field


class EditorSettingsResponse(BaseModel):
    auto_save: bool = False
    save_before_run: bool = True
    tab_width: int = 4
    insert_spaces: bool = True
    word_wrap: bool = True
    font_size: int = 13
    font_family: str = "Menlo"


class ExecutionSettingsResponse(BaseModel):
    large_run_threshold: int = 100
    reveal_execution_on_run: bool = True
    auto_open_report_on_failure: bool = False
    stop_confirmation: bool = True


class SearchSettingsResponse(BaseModel):
    content_search_extensions: list[str] = Field(default_factory=list)
    ignore_patterns: list[str] = Field(default_factory=list)


class AppearanceSettingsResponse(BaseModel):
    theme: str = "dark"
    restore_last_project: bool = True


class AppSettingsResponse(BaseModel):
    version: int = 1
    editor: EditorSettingsResponse = Field(default_factory=EditorSettingsResponse)
    execution: ExecutionSettingsResponse = Field(
        default_factory=ExecutionSettingsResponse,
    )
    search: SearchSettingsResponse = Field(default_factory=SearchSettingsResponse)
    appearance: AppearanceSettingsResponse = Field(
        default_factory=AppearanceSettingsResponse,
    )


class EditorSettingsPatch(BaseModel):
    auto_save: bool | None = None
    save_before_run: bool | None = None
    tab_width: int | None = None
    insert_spaces: bool | None = None
    word_wrap: bool | None = None
    font_size: int | None = None
    font_family: str | None = None


class ExecutionSettingsPatch(BaseModel):
    large_run_threshold: int | None = None
    reveal_execution_on_run: bool | None = None
    auto_open_report_on_failure: bool | None = None
    stop_confirmation: bool | None = None


class SearchSettingsPatch(BaseModel):
    content_search_extensions: list[str] | None = None
    ignore_patterns: list[str] | None = None


class AppearanceSettingsPatch(BaseModel):
    theme: str | None = None
    restore_last_project: bool | None = None


class AppSettingsPatch(BaseModel):
    editor: EditorSettingsPatch | None = None
    execution: ExecutionSettingsPatch | None = None
    search: SearchSettingsPatch | None = None
    appearance: AppearanceSettingsPatch | None = None


def to_settings_response(raw: dict) -> AppSettingsResponse:
    return AppSettingsResponse.model_validate(raw)
