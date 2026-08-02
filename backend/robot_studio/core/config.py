from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ROBOT_STUDIO_")

    host: str = "127.0.0.1"
    port: int = 8765
    data_dir: Path = Path.home() / ".robot-studio"
    api_prefix: str = "/api/v1"
    debug: bool = False
    # Confirm before starting runs that match more than this many tests.
    large_run_threshold: int = 100

    @property
    def database_path(self) -> Path:
        return self.data_dir / "robot-studio.db"


settings = Settings()
