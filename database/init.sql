-- ============================================
-- FYP Database Initial Schema
-- ============================================

-- Sessions table
CREATE TABLE IF NOT EXISTS sessions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    camera_source VARCHAR(500) NOT NULL,
    status VARCHAR(50) DEFAULT 'idle',
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    config JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Detection results table
CREATE TABLE IF NOT EXISTS detection_results (
    id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    frame_id INTEGER NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    model_name VARCHAR(100) NOT NULL,
    result_data JSONB NOT NULL,
    confidence FLOAT,
    processing_time_ms FLOAT
);

-- Camera configurations table
CREATE TABLE IF NOT EXISTS camera_configs (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    source_type VARCHAR(50) NOT NULL,
    source_url VARCHAR(500) NOT NULL,
    group_name VARCHAR(255),
    fps INTEGER DEFAULT 30,
    width INTEGER DEFAULT 640,
    height INTEGER DEFAULT 480,
    is_default BOOLEAN DEFAULT FALSE,
    enabled_models JSONB DEFAULT '[]',
    model_configs JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS group_name VARCHAR(255);
ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS enabled_models JSONB DEFAULT '[]';
ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS model_configs JSONB DEFAULT '{}';

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_results_session ON detection_results(session_id);
CREATE INDEX IF NOT EXISTS idx_results_frame ON detection_results(session_id, frame_id);
CREATE INDEX IF NOT EXISTS idx_results_model ON detection_results(model_name);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);

-- ============================================
-- Multi-Camera Pipeline Features
-- ============================================

-- Pipeline instances: Multiple concurrent pipelines with independent configs
CREATE TABLE IF NOT EXISTS pipeline_instances (
    id SERIAL PRIMARY KEY,
    session_id INTEGER REFERENCES sessions(id) ON DELETE CASCADE,
    camera_config_id INTEGER REFERENCES camera_configs(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'idle',  -- idle, running, paused, error, stopped
    enabled_models JSONB DEFAULT '[]',  -- ["pose", "yolo", "custom_model_1"]
    model_configs JSONB DEFAULT '{}',   -- Per-model settings: {"yolo": {"confidence": 0.5}}
    fps FLOAT DEFAULT 0,
    frames_processed INTEGER DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Activity logs: Centralized logging for all events
CREATE TABLE IF NOT EXISTS activity_logs (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,  -- pipeline_start, pipeline_stop, alert_triggered, error, etc.
    source VARCHAR(100) DEFAULT 'backend',  -- backend, ml_manager, frontend
    severity VARCHAR(20) DEFAULT 'info',  -- debug, info, warning, error, critical
    message TEXT NOT NULL,
    pipeline_instance_id INTEGER REFERENCES pipeline_instances(id) ON DELETE SET NULL,
    session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Alert rules: Trigger conditions and actions
CREATE TABLE IF NOT EXISTS alert_rules (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    pipeline_instance_id INTEGER REFERENCES pipeline_instances(id) ON DELETE CASCADE,
    model_name VARCHAR(100) NOT NULL,  -- Which model's output to watch
    trigger_condition JSONB NOT NULL,  -- {"type": "object_detected", "classes": ["person"], "confidence_min": 0.8}
    actions JSONB NOT NULL,            -- {"push_notification": true, "webhook_ids": [1, 2]}
    is_active BOOLEAN DEFAULT TRUE,
    cooldown_seconds INTEGER DEFAULT 60,
    trigger_count INTEGER DEFAULT 0,
    last_triggered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Device tokens: FCM tokens for push notifications
CREATE TABLE IF NOT EXISTS device_tokens (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255),              -- Optional user identifier
    device_token VARCHAR(500) NOT NULL,
    platform VARCHAR(50) NOT NULL,     -- fcm, apns, web
    device_name VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(device_token)
);

-- Scheduled jobs: Cron-based pipeline scheduling
CREATE TABLE IF NOT EXISTS scheduled_jobs (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    camera_config_id INTEGER REFERENCES camera_configs(id) ON DELETE CASCADE,
    enabled_models JSONB DEFAULT '[]',
    model_configs JSONB DEFAULT '{}',
    cron_expression VARCHAR(100) NOT NULL,  -- "0 9 * * 1-5" (9 AM Mon-Fri)
    duration_minutes INTEGER,               -- How long to run (NULL = until stopped)
    is_active BOOLEAN DEFAULT TRUE,
    next_run_at TIMESTAMPTZ,
    last_run_at TIMESTAMPTZ,
    last_run_status VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Webhooks: External service integrations
CREATE TABLE IF NOT EXISTS webhooks (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    url VARCHAR(500) NOT NULL,
    secret_key VARCHAR(255),           -- For HMAC signature
    headers JSONB DEFAULT '{}',        -- Additional headers to send
    events JSONB DEFAULT '[]',         -- ["detection", "alert", "session_start", "session_end"]
    is_active BOOLEAN DEFAULT TRUE,
    retry_count INTEGER DEFAULT 3,
    last_called_at TIMESTAMPTZ,
    last_status_code INTEGER,
    failure_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Recordings: Video recording metadata
CREATE TABLE IF NOT EXISTS recordings (
    id SERIAL PRIMARY KEY,
    session_id INTEGER REFERENCES sessions(id) ON DELETE CASCADE,
    pipeline_instance_id INTEGER REFERENCES pipeline_instances(id) ON DELETE SET NULL,
    name VARCHAR(255),
    file_path VARCHAR(500) NOT NULL,
    results_file_path VARCHAR(500),    -- Path to JSON results file
    file_size_bytes BIGINT,
    duration_seconds FLOAT,
    fps FLOAT,
    width INTEGER,
    height INTEGER,
    codec VARCHAR(50),
    frame_count INTEGER,
    status VARCHAR(50) DEFAULT 'recording',  -- recording, completed, failed
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ROI zones: Region of interest definitions
CREATE TABLE IF NOT EXISTS roi_zones (
    id SERIAL PRIMARY KEY,
    camera_config_id INTEGER REFERENCES camera_configs(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    zone_type VARCHAR(50) DEFAULT 'polygon',  -- polygon, rectangle, circle
    coordinates JSONB NOT NULL,        -- [[x1,y1], [x2,y2], ...] normalized 0-1
    color VARCHAR(20) DEFAULT '#FF0000',
    is_active BOOLEAN DEFAULT TRUE,
    trigger_on_enter BOOLEAN DEFAULT TRUE,
    trigger_on_exit BOOLEAN DEFAULT FALSE,
    trigger_on_stay BOOLEAN DEFAULT FALSE,
    stay_threshold_seconds INTEGER DEFAULT 5,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Additional indexes for new tables
CREATE INDEX IF NOT EXISTS idx_pipeline_instances_session ON pipeline_instances(session_id);
CREATE INDEX IF NOT EXISTS idx_pipeline_instances_status ON pipeline_instances(status);
CREATE INDEX IF NOT EXISTS idx_pipeline_instances_camera ON pipeline_instances(camera_config_id);

CREATE INDEX IF NOT EXISTS idx_activity_logs_type ON activity_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_activity_logs_severity ON activity_logs(severity);
CREATE INDEX IF NOT EXISTS idx_activity_logs_created ON activity_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_logs_pipeline ON activity_logs(pipeline_instance_id);

CREATE INDEX IF NOT EXISTS idx_alert_rules_pipeline ON alert_rules(pipeline_instance_id);
CREATE INDEX IF NOT EXISTS idx_alert_rules_active ON alert_rules(is_active);

CREATE INDEX IF NOT EXISTS idx_scheduled_jobs_next_run ON scheduled_jobs(next_run_at);
CREATE INDEX IF NOT EXISTS idx_scheduled_jobs_active ON scheduled_jobs(is_active);

CREATE INDEX IF NOT EXISTS idx_recordings_session ON recordings(session_id);
CREATE INDEX IF NOT EXISTS idx_recordings_pipeline ON recordings(pipeline_instance_id);
CREATE INDEX IF NOT EXISTS idx_recordings_status ON recordings(status);

CREATE INDEX IF NOT EXISTS idx_roi_zones_camera ON roi_zones(camera_config_id);
CREATE INDEX IF NOT EXISTS idx_roi_zones_active ON roi_zones(is_active);

CREATE INDEX IF NOT EXISTS idx_device_tokens_active ON device_tokens(is_active);
CREATE INDEX IF NOT EXISTS idx_webhooks_active ON webhooks(is_active);

-- ============================================
-- Eldercare auth/patient/incident extensions
-- ============================================

CREATE TABLE IF NOT EXISTS user_accounts (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(500) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'caregiver',
    phone VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS auth_tokens (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    token_hash VARCHAR(128) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS patient_profiles (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(50),
    address TEXT,
    fall_risk BOOLEAN DEFAULT FALSE,
    seizure_risk BOOLEAN DEFAULT FALSE,
    risk_notes TEXT,
    primary_contact_name VARCHAR(255),
    primary_contact_phone VARCHAR(50),
    primary_contact_email VARCHAR(255),
    caregiver_id INTEGER REFERENCES user_accounts(id) ON DELETE SET NULL,
    relative_user_id INTEGER REFERENCES user_accounts(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS location VARCHAR(255);
ALTER TABLE camera_configs ADD COLUMN IF NOT EXISTS patient_id INTEGER;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_camera_configs_patient'
    ) THEN
        ALTER TABLE camera_configs
            ADD CONSTRAINT fk_camera_configs_patient
            FOREIGN KEY (patient_id) REFERENCES patient_profiles(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS detection_settings (
    id SERIAL PRIMARY KEY,
    camera_config_id INTEGER REFERENCES camera_configs(id) ON DELETE CASCADE,
    patient_id INTEGER REFERENCES patient_profiles(id) ON DELETE CASCADE,
    sensitivity FLOAT DEFAULT 0.5,
    pose_enabled BOOLEAN DEFAULT TRUE,
    fall_enabled BOOLEAN DEFAULT TRUE,
    seizure_enabled BOOLEAN DEFAULT FALSE,
    fall_threshold FLOAT DEFAULT 0.5,
    seizure_threshold FLOAT DEFAULT 0.7,
    local_patches_enabled BOOLEAN DEFAULT TRUE,
    global_patches_enabled BOOLEAN DEFAULT TRUE,
    kinematics_enabled BOOLEAN DEFAULT TRUE,
    seizure_pipeline_enabled BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS incidents (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    status VARCHAR(50) DEFAULT 'new',
    severity VARCHAR(50) DEFAULT 'warning',
    detected_at TIMESTAMPTZ DEFAULT NOW(),
    acknowledged_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    camera_config_id INTEGER REFERENCES camera_configs(id) ON DELETE SET NULL,
    patient_id INTEGER REFERENCES patient_profiles(id) ON DELETE SET NULL,
    pipeline_instance_id INTEGER REFERENCES pipeline_instances(id) ON DELETE SET NULL,
    session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    confidence FLOAT,
    threshold FLOAT,
    details JSONB DEFAULT '{}',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS system_plans (
    id SERIAL PRIMARY KEY,
    key VARCHAR(100) NOT NULL UNIQUE,
    title VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'planned',
    target_phase VARCHAR(50),
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_user_accounts_email ON user_accounts(email);
CREATE INDEX IF NOT EXISTS idx_auth_tokens_hash ON auth_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_patient_profiles_caregiver ON patient_profiles(caregiver_id);
CREATE INDEX IF NOT EXISTS idx_patient_profiles_relative ON patient_profiles(relative_user_id);
CREATE INDEX IF NOT EXISTS idx_camera_configs_patient ON camera_configs(patient_id);
CREATE INDEX IF NOT EXISTS idx_detection_settings_camera ON detection_settings(camera_config_id);
CREATE INDEX IF NOT EXISTS idx_detection_settings_patient ON detection_settings(patient_id);
CREATE INDEX IF NOT EXISTS idx_incidents_detected_at ON incidents(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);
CREATE INDEX IF NOT EXISTS idx_incidents_patient ON incidents(patient_id);
CREATE INDEX IF NOT EXISTS idx_incidents_camera ON incidents(camera_config_id);
