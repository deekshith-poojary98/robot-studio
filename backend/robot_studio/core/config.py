from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ROBOT_STUDIO_")

    host: str = "127.0.0.1"
    port: int = 8765
    # Always under the user home by default — never next to a read-only .app bundle.
    data_dir: Path = Path.home() / ".robot-studio"
    api_prefix: str = "/api/v1"
    debug: bool = False
    # Confirm before starting runs that match more than this many tests.
    large_run_threshold: int = 100
    # Comma-separated suffixes for Find in Files (plain-text content search).
    content_search_extensions: str = (
        ".robot,.resource,.py,.yaml,.yml,.txt,.md,.json,.tsv,.csv"
    )
    content_search_max_file_bytes: int = 2_000_000
    content_search_max_matches: int = 500
    content_search_context_lines: int = 1

    @field_validator("data_dir", mode="before")
    @classmethod
    def _expand_data_dir(cls, value: object) -> Path:
        path = Path(str(value)).expanduser()
        if not path.is_absolute():
            path = Path.home() / path
        return path.resolve()

    @property
    def database_path(self) -> Path:
        return self.data_dir / "robot-studio.db"


settings = Settings()
