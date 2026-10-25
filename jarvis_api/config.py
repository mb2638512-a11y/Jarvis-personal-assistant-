from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="JARVIS_", env_file=".env", extra="ignore")

    api_key: str = ""
    base_url: str = "https://api.openai.com/v1"
    model: str = ""
    request_timeout_seconds: float = Field(default=30, gt=0, le=120)


settings = Settings()
