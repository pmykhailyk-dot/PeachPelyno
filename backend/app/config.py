from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration, sourced entirely from the environment."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Spry API"
    app_env: Literal["development", "test", "production"] = "development"
    log_level: str = "info"

    # --- agenda-parser Lambda (Lab 6) ---
    # Model id, not code: swapping models or comparing Opus vs. Haiku (Part 4,
    # Step 5) is an env var change, not a redeploy of different code.
    parser_model: str = "us.anthropic.claude-opus-4-5-20251101-v1:0"
    # Cognito user pool the parser's function URL checks bearer tokens
    # against - same pool as the frontend's sign-in (Lab 4). Blank locally,
    # where the parser is exercised through `make parse` instead of the URL.
    auth_user_pool_id: str = ""
    auth_client_id: str = ""

    database_url: str = "postgresql+asyncpg://spry:spry@db:5432/spry"
    # Off on Lambda: a warm but idle execution environment would otherwise hold
    # pooled connections open, and Aurora Serverless only pauses at zero.
    db_pooling: bool = True
    # NoDecode keeps pydantic-settings from JSON-parsing the env value, so the
    # validator below can accept the comma-separated form Compose passes.
    cors_origins: Annotated[list[str], NoDecode] = Field(
        default_factory=lambda: ["http://localhost:3000"]
    )

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        """Accept a comma-separated string, since that is how Compose passes it."""
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @property
    def is_development(self) -> bool:
        return self.app_env == "development"


@lru_cache
def get_settings() -> Settings:
    return Settings()
