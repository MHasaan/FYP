"""
Database connection and session management
"""

from sqlalchemy import text, select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.config import get_settings

settings = get_settings()

# Convert postgresql:// to postgresql+asyncpg://
async_db_url = settings.database_url.replace("postgresql://", "postgresql+asyncpg://")

engine = create_async_engine(async_db_url, echo=settings.backend_debug)

async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    """Dependency that provides a database session."""
    async with async_session() as session:
        try:
            yield session
        finally:
            await session.close()


async def init_db():
    """Create all tables on startup."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

        # Keep older databases compatible with newer CameraConfig fields.
        await conn.execute(text("ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS group_name VARCHAR(255)"))
        await conn.execute(text("ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS enabled_models JSONB DEFAULT '[]'::jsonb"))
        await conn.execute(text("ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS model_configs JSONB DEFAULT '{}'::jsonb"))

    # Seed default alert rule if none exist
    from app.models import AlertRule
    async with async_session() as db:
        result = await db.execute(select(AlertRule).limit(1))
        if result.scalar_one_or_none() is None:
            print("🌱 Seeding default Fall Detection alert rule...")
            default_rule = AlertRule(
                name="Global Fall Detection",
                description="Automatically triggered when any fall is detected with confidence > 0.5",
                model_name="fall_detection",
                trigger_condition={
                    "type": "confidence_above",
                    "confidence_min": 0.5
                },
                actions={
                    "push_notification": True,
                    "log_event": True
                },
                cooldown_seconds=30
            )
            db.add(default_rule)
            await db.commit()
