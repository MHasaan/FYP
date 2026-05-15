"""
FYP Backend Configuration

All sensitive settings MUST be provided via environment variables.
The application will fail to start if required variables are missing.
"""

from pydantic_settings import BaseSettings
from pydantic import field_validator
from functools import lru_cache


class Settings(BaseSettings):
    # Database - REQUIRED (no defaults for security)
    database_url: str
    postgres_user: str
    postgres_password: str
    postgres_db: str
    postgres_host: str = "database"
    postgres_port: int = 5432

    # Redis
    redis_url: str = "redis://redis:6379/0"
    redis_host: str = "redis"
    redis_port: int = 6379

    # Backend
    backend_host: str = "0.0.0.0"
    backend_port: int = 8000
    backend_debug: bool = False  # Default to False for security
    secret_key: str  # REQUIRED - no default
    api_key: str = ""  # Optional API key for authentication

    # CORS - comma-separated list of allowed origins
    cors_origins: str = ""  # e.g., "http://localhost:3000,http://localhost:8080"

    # ML Manager
    ml_manager_host: str = "ml_manager"
    ml_manager_port: int = 8001

    # Camera
    default_camera_source: str = "0"
    camera_fps: int = 30
    camera_width: int = 640
    camera_height: int = 480

    # Firebase Cloud Messaging (push notifications). When unset the backend
    # falls back to simulation mode so dev environments work without Firebase.
    fcm_credentials_path: str = ""
    fcm_default_icon: str = "ic_notification"

    @field_validator("database_url", "postgres_password", "secret_key")
    @classmethod
    def validate_required(cls, v: str, info) -> str:
        if not v or v.strip() == "":
            raise ValueError(f"{info.field_name} is required and cannot be empty")
        return v

    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    return Settings()
