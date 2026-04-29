"""
Pydantic Schemas for API request/response validation
"""

from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, Any, Literal
from datetime import datetime


# Base schema config to avoid warnings about model_ prefix
class BaseSchema(BaseModel):
    model_config = ConfigDict(protected_namespaces=())


# ============ Camera Schemas ============

class CameraConfigCreate(BaseModel):
    name: str
    source_type: str  # usb, rtsp, http, video_file
    source_url: str
    group_name: Optional[str] = None
    fps: int = 30
    width: int = 640
    height: int = 480
    is_default: bool = False
    enabled_models: list[str] = Field(default_factory=list)
    model_configs: dict = Field(default_factory=dict)


class CameraConfigUpdate(BaseModel):
    name: Optional[str] = None
    source_type: Optional[str] = None
    source_url: Optional[str] = None
    group_name: Optional[str] = None
    fps: Optional[int] = None
    width: Optional[int] = None
    height: Optional[int] = None
    is_default: Optional[bool] = None
    enabled_models: Optional[list[str]] = None
    model_configs: Optional[dict] = None


class CameraConfigResponse(CameraConfigCreate):
    id: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class CameraSourceRequest(BaseModel):
    """Request to set/change camera source."""
    source: str  # URL, device index, or file path
    fps: Optional[int] = 30
    width: Optional[int] = 640
    height: Optional[int] = 480


# ============ Session Schemas ============

class SessionCreate(BaseModel):
    name: str
    camera_source: str
    config: dict = {}


class SessionResponse(BaseModel):
    id: int
    name: str
    camera_source: str
    status: str
    started_at: Optional[datetime]
    ended_at: Optional[datetime]
    config: dict
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ============ Pipeline Schemas ============

class PipelineStatusResponse(BaseModel):
    is_running: bool
    active_session_id: Optional[int]
    camera_source: Optional[str]
    models_loaded: list[str] = []
    fps: float = 0.0
    frames_processed: int = 0


class PipelineControlRequest(BaseModel):
    action: str  # start, stop, pause, resume
    session_id: Optional[int] = None
    camera_source: Optional[str] = None
    config: dict = {}


# ============ Pipeline Instance Schemas ============

class PipelineInstanceCreate(BaseSchema):
    """Create a new pipeline instance."""
    name: str
    camera_config_id: int
    enabled_models: list[str] = Field(default_factory=list)
    model_configs: dict = Field(default_factory=dict)


class PipelineInstanceUpdate(BaseSchema):
    """Update pipeline instance settings."""
    name: Optional[str] = None
    enabled_models: Optional[list[str]] = None
    model_configs: Optional[dict] = None


class PipelineInstanceResponse(BaseSchema):
    id: int
    session_id: Optional[int]
    camera_config_id: Optional[int]
    name: str
    status: str
    enabled_models: list[str]
    model_configs: dict
    fps: float
    frames_processed: int
    last_error: Optional[str]
    created_at: datetime
    updated_at: Optional[datetime]

    model_config = ConfigDict(from_attributes=True, protected_namespaces=())


class PipelineInstanceControl(BaseModel):
    """Control a pipeline instance."""
    action: str  # start, stop, pause, resume


class PipelineInstanceModelsUpdate(BaseModel):
    """Update enabled models for an instance."""
    enabled_models: list[str]


class PipelineInstanceConfigUpdate(BaseSchema):
    """Update model configurations for an instance."""
    model_configs: dict  # {"yolo": {"confidence": 0.5, "classes": ["person"]}}


class PipelineInstanceBatchImportRequest(BaseSchema):
    """Batch import cameras + instances in a single backend request."""
    cameras: list[dict[str, Any]] = Field(default_factory=list)
    conflict_strategy: Literal["skip", "rename", "merge"] = "skip"
    mode: Literal["tolerant", "strict"] = "tolerant"


class PipelineInstanceBatchImportResponse(BaseSchema):
    """Batch import result report."""
    timestamp: str
    conflict_strategy: str
    mode: str
    summary: dict[str, Any]
    rows: list[dict[str, Any]]


# ============ Activity Log Schemas ============

class ActivityLogCreate(BaseModel):
    """Create an activity log entry."""
    event_type: str
    source: str = "backend"
    severity: str = "info"
    message: str
    pipeline_instance_id: Optional[int] = None
    session_id: Optional[int] = None
    extra_data: dict = Field(default_factory=dict)


class ActivityLogResponse(BaseModel):
    id: int
    event_type: str
    source: str
    severity: str
    message: str
    pipeline_instance_id: Optional[int]
    session_id: Optional[int]
    extra_data: dict
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ActivityLogFilter(BaseModel):
    """Filter parameters for activity logs."""
    event_type: Optional[str] = None
    severity: Optional[str] = None
    pipeline_instance_id: Optional[int] = None
    session_id: Optional[int] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    limit: int = 100
    offset: int = 0


# ============ Alert Rule Schemas ============

class AlertTriggerCondition(BaseModel):
    """Condition that triggers an alert."""
    type: str  # object_detected, confidence_above, count_threshold
    classes: Optional[list[str]] = None
    confidence_min: Optional[float] = None
    count_threshold: Optional[int] = None


class AlertActions(BaseModel):
    """Actions to take when alert is triggered."""
    push_notification: bool = False
    webhook_ids: list[int] = Field(default_factory=list)
    log_event: bool = True


class AlertRuleCreate(BaseSchema):
    """Create an alert rule."""
    name: str
    description: Optional[str] = None
    pipeline_instance_id: Optional[int] = None
    model_name: str
    trigger_condition: AlertTriggerCondition
    actions: AlertActions
    cooldown_seconds: int = 60


class AlertRuleUpdate(BaseSchema):
    """Update an alert rule."""
    name: Optional[str] = None
    description: Optional[str] = None
    trigger_condition: Optional[AlertTriggerCondition] = None
    actions: Optional[AlertActions] = None
    is_active: Optional[bool] = None
    cooldown_seconds: Optional[int] = None


class AlertRuleResponse(BaseSchema):
    id: int
    name: str
    description: Optional[str]
    pipeline_instance_id: Optional[int]
    model_name: str
    trigger_condition: dict
    actions: dict
    is_active: bool
    cooldown_seconds: int
    trigger_count: int
    last_triggered_at: Optional[datetime]
    created_at: datetime
    updated_at: Optional[datetime]

    model_config = ConfigDict(from_attributes=True, protected_namespaces=())


# ============ Device Token Schemas ============

class DeviceTokenCreate(BaseModel):
    """Register a device token for push notifications."""
    device_token: str
    platform: str  # fcm, apns, web
    user_id: Optional[str] = None
    device_name: Optional[str] = None


class DeviceTokenResponse(BaseModel):
    id: int
    user_id: Optional[str]
    device_token: str
    platform: str
    device_name: Optional[str]
    is_active: bool
    last_used_at: Optional[datetime]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class DeviceTokenUpdate(BaseModel):
    """Update an existing device token registration."""
    user_id: Optional[str] = None
    device_name: Optional[str] = None
    is_active: Optional[bool] = None


class PushNotificationTestRequest(BaseModel):
    """Send a test push notification to active registered tokens."""
    title: str = "FYP Test Notification"
    body: str = "This is a test push notification from FYP backend."
    platform: Optional[str] = None  # fcm, apns, web
    user_id: Optional[str] = None


class PushNotificationTestResponse(BaseModel):
    """Result of a test push dispatch request."""
    sent_to: int
    platform: Optional[str]
    user_id: Optional[str]
    simulated: bool = True
    message: str


# ============ Scheduled Job Schemas ============

class ScheduledJobCreate(BaseSchema):
    """Create a scheduled pipeline job."""
    name: str
    description: Optional[str] = None
    camera_config_id: int
    enabled_models: list[str] = Field(default_factory=list)
    model_configs: dict = Field(default_factory=dict)
    cron_expression: str  # "0 9 * * 1-5" (9 AM Mon-Fri)
    duration_minutes: Optional[int] = None


class ScheduledJobUpdate(BaseSchema):
    """Update a scheduled job."""
    name: Optional[str] = None
    description: Optional[str] = None
    camera_config_id: Optional[int] = None
    enabled_models: Optional[list[str]] = None
    model_configs: Optional[dict] = None
    cron_expression: Optional[str] = None
    duration_minutes: Optional[int] = None
    is_active: Optional[bool] = None


class ScheduledJobResponse(BaseSchema):
    id: int
    name: str
    description: Optional[str]
    camera_config_id: Optional[int]
    enabled_models: list[str]
    model_configs: dict
    cron_expression: str
    duration_minutes: Optional[int]
    is_active: bool
    next_run_at: Optional[datetime]
    last_run_at: Optional[datetime]
    last_run_status: Optional[str]
    created_at: datetime
    updated_at: Optional[datetime]

    model_config = ConfigDict(from_attributes=True)


# ============ Webhook Schemas ============

class WebhookCreate(BaseModel):
    """Create a webhook configuration."""
    name: str
    url: str
    secret_key: Optional[str] = None
    headers: dict = Field(default_factory=dict)
    events: list[str] = Field(default_factory=list)  # ["detection", "alert", "session_start"]
    retry_count: int = 3


class WebhookUpdate(BaseModel):
    """Update a webhook configuration."""
    name: Optional[str] = None
    url: Optional[str] = None
    secret_key: Optional[str] = None
    headers: Optional[dict] = None
    events: Optional[list[str]] = None
    is_active: Optional[bool] = None
    retry_count: Optional[int] = None


class WebhookResponse(BaseModel):
    id: int
    name: str
    url: str
    headers: dict
    events: list[str]
    is_active: bool
    retry_count: int
    last_called_at: Optional[datetime]
    last_status_code: Optional[int]
    failure_count: int
    created_at: datetime
    updated_at: Optional[datetime]

    model_config = ConfigDict(from_attributes=True)


class WebhookTestRequest(BaseModel):
    """Test a webhook by sending a test payload."""
    webhook_id: int


# ============ Recording Schemas ============

class RecordingCreate(BaseModel):
    """Start a recording."""
    session_id: Optional[int] = None
    pipeline_instance_id: int
    name: Optional[str] = None


class RecordingResponse(BaseModel):
    id: int
    session_id: Optional[int]
    pipeline_instance_id: Optional[int]
    name: Optional[str]
    file_path: str
    results_file_path: Optional[str]
    file_size_bytes: Optional[int]
    duration_seconds: Optional[float]
    fps: Optional[float]
    width: Optional[int]
    height: Optional[int]
    codec: Optional[str]
    frame_count: Optional[int]
    status: str
    started_at: datetime
    ended_at: Optional[datetime]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class RecordingStopRequest(BaseModel):
    """Stop a recording and optionally persist final metadata."""
    status: str = "completed"
    results_file_path: Optional[str] = None
    file_size_bytes: Optional[int] = None
    duration_seconds: Optional[float] = None
    fps: Optional[float] = None
    width: Optional[int] = None
    height: Optional[int] = None
    codec: Optional[str] = None
    frame_count: Optional[int] = None


# ============ ROI Zone Schemas ============

class ROIZoneCreate(BaseModel):
    """Create a region of interest zone."""
    camera_config_id: int
    name: str
    description: Optional[str] = None
    zone_type: str = "polygon"  # polygon, rectangle, circle
    coordinates: list[list[float]]  # [[x1,y1], [x2,y2], ...] normalized 0-1
    color: str = "#FF0000"
    trigger_on_enter: bool = True
    trigger_on_exit: bool = False
    trigger_on_stay: bool = False
    stay_threshold_seconds: int = 5


class ROIZoneUpdate(BaseModel):
    """Update a ROI zone."""
    name: Optional[str] = None
    description: Optional[str] = None
    coordinates: Optional[list[list[float]]] = None
    color: Optional[str] = None
    is_active: Optional[bool] = None
    trigger_on_enter: Optional[bool] = None
    trigger_on_exit: Optional[bool] = None
    trigger_on_stay: Optional[bool] = None
    stay_threshold_seconds: Optional[int] = None


class ROIZoneResponse(BaseModel):
    id: int
    camera_config_id: int
    name: str
    description: Optional[str]
    zone_type: str
    coordinates: list[list[float]]
    color: str
    is_active: bool
    trigger_on_enter: bool
    trigger_on_exit: bool
    trigger_on_stay: bool
    stay_threshold_seconds: int
    created_at: datetime
    updated_at: Optional[datetime]

    model_config = ConfigDict(from_attributes=True)


# ============ Result Schemas ============

class DetectionResultResponse(BaseSchema):
    id: int
    session_id: int
    frame_id: int
    timestamp: datetime
    model_name: str
    result_data: Any
    confidence: Optional[float]
    processing_time_ms: Optional[float]

    model_config = ConfigDict(from_attributes=True)


class FrameResultResponse(BaseModel):
    """Aggregated result for a single frame from all models."""
    frame_id: int
    timestamp: datetime
    results: dict[str, Any]  # model_name -> result_data
    total_processing_time_ms: float


# ============ General ============

class HealthResponse(BaseModel):
    status: str
    version: str
    services: dict[str, str]


class PaginatedResponse(BaseModel):
    """Generic paginated response."""
    items: list[Any]
    total: int
    limit: int
    offset: int
    has_more: bool
