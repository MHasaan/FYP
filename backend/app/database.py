"""
Database connection and session management
"""

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
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
        await conn.execute(text("ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS location VARCHAR(255)"))
        await conn.execute(text("ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS patient_id INTEGER"))
        await conn.execute(text("ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS enabled_models JSONB DEFAULT '[]'::jsonb"))
        await conn.execute(text("ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS model_configs JSONB DEFAULT '{}'::jsonb"))

    # Seed default users, alert rules, and roadmap placeholders.
    from app.models import AlertRule, SystemPlan, UserAccount
    from app.services.auth_service import hash_password

    async with async_session() as db:
        user_result = await db.execute(select(UserAccount).limit(1))
        if user_result.scalar_one_or_none() is None:
            print("Seeding default Eldercare admin user...")
            db.add(
                UserAccount(
                    full_name="Eldercare Admin",
                    email="admin@eldercare.local",
                    password_hash=hash_password("Admin@12345"),
                    role="admin",
                    is_active=True,
                )
            )

        fall_rule_result = await db.execute(
            select(AlertRule).where(AlertRule.model_name == "fall_detection").limit(1)
        )
        if fall_rule_result.scalar_one_or_none() is None:
            print("Seeding default Fall Detection alert rule...")
            db.add(
                AlertRule(
                    name="Global Fall Detection",
                    description="Automatically triggered when any fall is detected with confidence > 0.5",
                    model_name="fall_detection",
                    trigger_condition={
                        "type": "confidence_above",
                        "confidence_min": 0.5,
                    },
                    actions={
                        "push_notification": True,
                        "log_event": True,
                    },
                    cooldown_seconds=30,
                )
            )

        seizure_rule_result = await db.execute(
            select(AlertRule).where(AlertRule.model_name == "seizure_detection").limit(1)
        )
        if seizure_rule_result.scalar_one_or_none() is None:
            print("Seeding default Seizure Detection placeholder alert rule...")
            db.add(
                AlertRule(
                    name="Global Seizure Detection",
                    description="Placeholder trigger for VSViG seizure likelihood when confidence > 0.7",
                    model_name="seizure_detection",
                    trigger_condition={
                        "type": "confidence_above",
                        "confidence_min": 0.7,
                    },
                    actions={
                        "push_notification": True,
                        "log_event": True,
                    },
                    cooldown_seconds=30,
                )
            )

        plan_rows = [
            {
                "key": "mobile_app",
                "title": "Future Mobile Application",
                "status": "planned",
                "target_phase": "FYP-II",
                "description": "Caregiver push alerts, incident details, and acknowledgement from smartphones.",
            },
            {
                "key": "local_offline_database",
                "title": "Local Database / Offline Mode",
                "status": "planned",
                "target_phase": "FYP-II",
                "description": "On-device or on-premises storage for sensitive data and limited-connectivity monitoring.",
            },
            {
                "key": "seizure_vs_vig_pipeline",
                "title": "VSViG Seizure Detection Pipeline",
                "status": "placeholder",
                "target_phase": "FYP-II",
                "description": "Integration placeholder for WU-SAHZU-EMU skeleton-sequence seizure likelihood inference.",
            },
        ]
        for plan in plan_rows:
            existing_plan = await db.execute(select(SystemPlan).where(SystemPlan.key == plan["key"]))
            if existing_plan.scalar_one_or_none() is None:
                db.add(SystemPlan(**plan))

        await db.commit()
