from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    backend_env: str = "development"
    backend_debug: bool = True
    database_url: str = "postgresql+psycopg://attendance:attendance@localhost:5432/attendance_db"
    jwt_secret_key: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_exp_minutes: int = 60
    default_admin_email: str = "admin@school.com"
    default_admin_password: str = "changeMe123"
    image_retention_days: int = 30
    enable_image_retention: bool = False


@lru_cache
def get_settings() -> Settings:
    return Settings()
