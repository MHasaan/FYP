"""
SQLAlchemy Database Models
"""

from sqlalchemy import Column, Integer, String, Float, DateTime, Text, Boolean, JSON, ForeignKey, BigInteger, Date
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.database import Base


class UserAccount(Base):
    """Application user with an Eldercare role."""
    __tablename__ = "user_accounts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    full_name = Column(String(255), nullable=False)
    email = Column(String(255), nullable=False, unique=True, index=True)
    password_hash = Column(String(500), nullable=False)
    role = Column(String(50), nullable=False, default="caregiver")  # admin, caregiver, patient_relative
    phone = Column(String(50), nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    tokens = relationship("AuthToken", back_populates="user", cascade="all, delete-orphan")
    assigned_patients = relationship(
        "PatientProfile",
        foreign_keys="PatientProfile.caregiver_id",
        back_populates="caregiver",
    )
    relative_patients = relationship(
        "PatientProfile",
        foreign_keys="PatientProfile.relative_user_id",
        back_populates="relative_user",
    )


class AuthToken(Base):
    """Opaque bearer token hash for frontend sessions."""
    __tablename__ = "auth_tokens"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("user_accounts.id"), nullable=False)
    token_hash = Column(String(128), nullable=False, unique=True, index=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    revoked_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("UserAccount", back_populates="tokens")


class PatientProfile(Base):
    """Patient profile used by Eldercare monitoring workflows."""
    __tablename__ = "patient_profiles"

    id = Column(Integer, primary_key=True, autoincrement=True)
    full_name = Column(String(255), nullable=False)
    date_of_birth = Column(Date, nullable=True)
    gender = Column(String(50), nullable=True)
    address = Column(Text, nullable=True)
    fall_risk = Column(String(20), default="none", nullable=False)
    seizure_risk = Column(String(20), default="none", nullable=False)
    risk_notes = Column(Text, nullable=True)
    primary_contact_name = Column(String(255), nullable=True)
    primary_contact_phone = Column(String(50), nullable=True)
    primary_contact_email = Column(String(255), nullable=True)
    caregiver_id = Column(Integer, ForeignKey("user_accounts.id"), nullable=True)
    relative_user_id = Column(Integer, ForeignKey("user_accounts.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    caregiver = relationship(
        "UserAccount",
        foreign_keys=[caregiver_id],
        back_populates="assigned_patients",
    )
    relative_user = relationship(
        "UserAccount",
        foreign_keys=[relative_user_id],
        back_populates="relative_patients",
    )
    camera_configs = relationship("CameraConfig", back_populates="patient")
    incidents = relationship("Incident", back_populates="patient")
    detection_settings = relationship("DetectionSetting", back_populates="patient", cascade="all, delete-orphan")


class Session(Base):
    """A session represents one recording/analysis period."""
    __tablename__ = "sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)
    camera_source = Column(String(500), nullable=False)
    status = Column(String(50), default="idle")  # idle, running, paused, completed
    started_at = Column(DateTime(timezone=True), server_default=func.now())
    ended_at = Column(DateTime(timezone=True), nullable=True)
    config = Column(JSON, default={})
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationships
    results = relationship("DetectionResult", back_populates="session", cascade="all, delete-orphan")
    pipeline_instances = relationship("PipelineInstance", back_populates="session", cascade="all, delete-orphan")
    recordings = relationship("Recording", back_populates="session", cascade="all, delete-orphan")


class DetectionResult(Base):
    """Individual detection/prediction result from the ML pipeline."""
    __tablename__ = "detection_results"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("sessions.id"), nullable=False)
    frame_id = Column(Integer, nullable=False)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())

    # Result data from each model
    model_name = Column(String(100), nullable=False)  # pose, yolo, custom_model_1, etc.
    result_data = Column(JSON, nullable=False)  # Model-specific output
    confidence = Column(Float, nullable=True)
    processing_time_ms = Column(Float, nullable=True)

    # Relationships
    session = relationship("Session", back_populates="results")


class CameraConfig(Base):
    """Saved camera configurations."""
    __tablename__ = "camera_configs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False, unique=True)
    source_type = Column(String(50), nullable=False)  # usb, rtsp, http, video_file
    source_url = Column(String(500), nullable=False)
    group_name = Column(String(255), nullable=True)
    location = Column(String(255), nullable=True)
    patient_id = Column(Integer, ForeignKey("patient_profiles.id"), nullable=True)
    fps = Column(Integer, default=30)
    width = Column(Integer, default=640)
    height = Column(Integer, default=480)
    is_default = Column(Boolean, default=False)
    enabled_models = Column(JSON, default=[])
    model_configs = Column(JSON, default={})
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationships
    pipeline_instances = relationship("PipelineInstance", back_populates="camera_config")
    scheduled_jobs = relationship("ScheduledJob", back_populates="camera_config")
    roi_zones = relationship("ROIZone", back_populates="camera_config", cascade="all, delete-orphan")
    patient = relationship("PatientProfile", back_populates="camera_configs")
    incidents = relationship("Incident", back_populates="camera_config")
    detection_settings = relationship("DetectionSetting", back_populates="camera_config", cascade="all, delete-orphan")


# ============================================
# Multi-Camera Pipeline Features
# ============================================

class PipelineInstance(Base):
    """A pipeline instance running on a specific camera with specific model configs."""
    __tablename__ = "pipeline_instances"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("sessions.id"), nullable=True)
    camera_config_id = Column(Integer, ForeignKey("camera_configs.id"), nullable=True)
    name = Column(String(255), nullable=False)
    status = Column(String(50), default="idle")  # idle, running, paused, error, stopped
    enabled_models = Column(JSON, default=[])  # ["pose", "yolo", "custom_model_1"]
    model_configs = Column(JSON, default={})   # Per-model settings
    fps = Column(Float, default=0)
    frames_processed = Column(Integer, default=0)
    last_error = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    session = relationship("Session", back_populates="pipeline_instances")
    camera_config = relationship("CameraConfig", back_populates="pipeline_instances")
    alert_rules = relationship("AlertRule", back_populates="pipeline_instance", cascade="all, delete-orphan")
    activity_logs = relationship("ActivityLog", back_populates="pipeline_instance")
    recordings = relationship("Recording", back_populates="pipeline_instance")
    incidents = relationship("Incident", back_populates="pipeline_instance")


class DetectionSetting(Base):
    """Per-camera or per-patient detector toggles and thresholds."""
    __tablename__ = "detection_settings"

    id = Column(Integer, primary_key=True, autoincrement=True)
    camera_config_id = Column(Integer, ForeignKey("camera_configs.id"), nullable=True)
    patient_id = Column(Integer, ForeignKey("patient_profiles.id"), nullable=True)
    sensitivity = Column(Float, default=0.5)
    pose_enabled = Column(Boolean, default=True)
    fall_enabled = Column(Boolean, default=True)
    seizure_enabled = Column(Boolean, default=False)
    fall_threshold = Column(Float, default=0.5)
    seizure_threshold = Column(Float, default=0.7)
    local_patches_enabled = Column(Boolean, default=True)
    global_patches_enabled = Column(Boolean, default=True)
    kinematics_enabled = Column(Boolean, default=True)
    seizure_pipeline_enabled = Column(Boolean, default=False)
    notes = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    camera_config = relationship("CameraConfig", back_populates="detection_settings")
    patient = relationship("PatientProfile", back_populates="detection_settings")


class Incident(Base):
    """Fall/seizure incident created from detections or manual review."""
    __tablename__ = "incidents"

    id = Column(Integer, primary_key=True, autoincrement=True)
    event_type = Column(String(50), nullable=False)  # fall, seizure, manual
    status = Column(String(50), default="new")  # new, acknowledged, resolved
    severity = Column(String(50), default="warning")
    detected_at = Column(DateTime(timezone=True), server_default=func.now())
    acknowledged_at = Column(DateTime(timezone=True), nullable=True)
    resolved_at = Column(DateTime(timezone=True), nullable=True)
    camera_config_id = Column(Integer, ForeignKey("camera_configs.id"), nullable=True)
    patient_id = Column(Integer, ForeignKey("patient_profiles.id"), nullable=True)
    pipeline_instance_id = Column(Integer, ForeignKey("pipeline_instances.id"), nullable=True)
    session_id = Column(Integer, ForeignKey("sessions.id"), nullable=True)
    confidence = Column(Float, nullable=True)
    threshold = Column(Float, nullable=True)
    details = Column(JSON, default={})
    notes = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    camera_config = relationship("CameraConfig", back_populates="incidents")
    patient = relationship("PatientProfile", back_populates="incidents")
    pipeline_instance = relationship("PipelineInstance", back_populates="incidents")


class ActivityLog(Base):
    """Centralized logging for all events."""
    __tablename__ = "activity_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    event_type = Column(String(100), nullable=False)
    source = Column(String(100), default="backend")
    severity = Column(String(20), default="info")  # debug, info, warning, error, critical
    message = Column(Text, nullable=False)
    pipeline_instance_id = Column(Integer, ForeignKey("pipeline_instances.id"), nullable=True)
    session_id = Column(Integer, ForeignKey("sessions.id"), nullable=True)
    extra_data = Column("metadata", JSON, default={})  # Use column name "metadata" in DB, but "extra_data" in Python
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationships
    pipeline_instance = relationship("PipelineInstance", back_populates="activity_logs")


class AlertRule(Base):
    """Alert rules for triggering notifications based on detections."""
    __tablename__ = "alert_rules"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    pipeline_instance_id = Column(Integer, ForeignKey("pipeline_instances.id"), nullable=True)
    model_name = Column(String(100), nullable=False)
    trigger_condition = Column(JSON, nullable=False)
    actions = Column(JSON, nullable=False)
    is_active = Column(Boolean, default=True)
    cooldown_seconds = Column(Integer, default=60)
    trigger_count = Column(Integer, default=0)
    last_triggered_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    pipeline_instance = relationship("PipelineInstance", back_populates="alert_rules")


class DeviceToken(Base):
    """FCM/APNS tokens for push notifications."""
    __tablename__ = "device_tokens"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String(255), nullable=True)
    device_token = Column(String(500), nullable=False, unique=True)
    platform = Column(String(50), nullable=False)  # fcm, apns, web
    device_name = Column(String(255), nullable=True)
    is_active = Column(Boolean, default=True)
    last_used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


class ScheduledJob(Base):
    """Scheduled pipeline jobs with cron expressions."""
    __tablename__ = "scheduled_jobs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    camera_config_id = Column(Integer, ForeignKey("camera_configs.id"), nullable=True)
    enabled_models = Column(JSON, default=[])
    model_configs = Column(JSON, default={})
    cron_expression = Column(String(100), nullable=False)
    duration_minutes = Column(Integer, nullable=True)
    is_active = Column(Boolean, default=True)
    next_run_at = Column(DateTime(timezone=True), nullable=True)
    last_run_at = Column(DateTime(timezone=True), nullable=True)
    last_run_status = Column(String(50), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    camera_config = relationship("CameraConfig", back_populates="scheduled_jobs")


class Webhook(Base):
    """Webhook configurations for external integrations."""
    __tablename__ = "webhooks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)
    url = Column(String(500), nullable=False)
    secret_key = Column(String(255), nullable=True)
    headers = Column(JSON, default={})
    events = Column(JSON, default=[])  # ["detection", "alert", "session_start"]
    is_active = Column(Boolean, default=True)
    retry_count = Column(Integer, default=3)
    last_called_at = Column(DateTime(timezone=True), nullable=True)
    last_status_code = Column(Integer, nullable=True)
    failure_count = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


class Recording(Base):
    """Video recording metadata."""
    __tablename__ = "recordings"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("sessions.id"), nullable=True)
    pipeline_instance_id = Column(Integer, ForeignKey("pipeline_instances.id"), nullable=True)
    name = Column(String(255), nullable=True)
    file_path = Column(String(500), nullable=False)
    results_file_path = Column(String(500), nullable=True)
    file_size_bytes = Column(BigInteger, nullable=True)
    duration_seconds = Column(Float, nullable=True)
    fps = Column(Float, nullable=True)
    width = Column(Integer, nullable=True)
    height = Column(Integer, nullable=True)
    codec = Column(String(50), nullable=True)
    frame_count = Column(Integer, nullable=True)
    status = Column(String(50), default="recording")
    started_at = Column(DateTime(timezone=True), server_default=func.now())
    ended_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationships
    session = relationship("Session", back_populates="recordings")
    pipeline_instance = relationship("PipelineInstance", back_populates="recordings")


class ROIZone(Base):
    """Region of interest zones for cameras."""
    __tablename__ = "roi_zones"

    id = Column(Integer, primary_key=True, autoincrement=True)
    camera_config_id = Column(Integer, ForeignKey("camera_configs.id"), nullable=False)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    zone_type = Column(String(50), default="polygon")
    coordinates = Column(JSON, nullable=False)  # Normalized 0-1 coordinates
    color = Column(String(20), default="#FF0000")
    is_active = Column(Boolean, default=True)
    trigger_on_enter = Column(Boolean, default=True)
    trigger_on_exit = Column(Boolean, default=False)
    trigger_on_stay = Column(Boolean, default=False)
    stay_threshold_seconds = Column(Integer, default=5)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    camera_config = relationship("CameraConfig", back_populates="roi_zones")


class SystemPlan(Base):
    """Roadmap placeholder rows for planned Eldercare capabilities."""
    __tablename__ = "system_plans"

    id = Column(Integer, primary_key=True, autoincrement=True)
    key = Column(String(100), nullable=False, unique=True)
    title = Column(String(255), nullable=False)
    status = Column(String(50), default="planned")
    target_phase = Column(String(50), nullable=True)
    description = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


class GroundingDinoJob(Base):
    """A standalone open-set object detection job using GroundingDINO.

    This is intentionally decoupled from the live pipeline (Sessions /
    PipelineInstance) — Visual Search is a separate entity with its own
    request-response flow, not a streaming model.
    """
    __tablename__ = "grounding_dino_jobs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("user_accounts.id"), nullable=True)
    name = Column(String(255), nullable=True)
    input_type = Column(String(20), nullable=False)  # image | video
    input_path = Column(String(500), nullable=False)
    input_original_filename = Column(String(255), nullable=True)
    prompt = Column(Text, nullable=False)
    box_threshold = Column(Float, default=0.35)
    text_threshold = Column(Float, default=0.25)
    status = Column(String(20), default="queued")  # queued, running, completed, failed
    output_image_path = Column(String(500), nullable=True)
    output_video_path = Column(String(500), nullable=True)
    detections = Column(JSON, default=[])  # [{label, confidence, box:[x1,y1,x2,y2]}, ...]
    summary = Column(JSON, default={})  # counts per label, total detections, etc.
    error = Column(Text, nullable=True)
    processing_ms = Column(Float, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
