# Project Instructions & Preferences

## Project Overview
A full-stack real-time ML pipeline system with Flutter frontend, FastAPI backend, Dockerized ML models with GPU support, and multi-camera input.

## Tech Stack
- Frontend: Flutter Web (NavigationRail desktop layout)
- Backend: Python FastAPI + WebSocket + SQLAlchemy (async)
- ML Manager: Python (Multi-pipeline orchestration with per-instance configuration)
- Database: PostgreSQL with async sessions
- Message Broker: Redis (pub/sub for microservice communication)
- Container Orchestration: Docker Compose

## Architecture
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Flutter Web   │────▶│  FastAPI Backend│────▶│   ML Manager    │
│   (Frontend)    │◀────│    (REST/WS)    │◀────│  (GPUSupportw  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │                       ▼                       │
        │               ┌─────────────────┐             │
        │               │   PostgreSQL    │             │
        │               │   (Database)    │             │
        │               └─────────────────┘             │
        │                       │                       │
        └───────────────────────┼───────────────────────┘
                                ▼
                        ┌─────────────────┐
                        │     Redis       │
                        │   (Pub/Sub)     │
                        └─────────────────┘
```

## Setup & Running
- Windows Setup: `commandScripts\setup.bat`
- Start: `commandScripts\start.bat`
- Stop: `commandScripts\stop.bat`
- Rebuild: `commandScripts\start.bat rebuild`

## Key File Locations
```
project/
├── backend/
│   ├── app/
│   │   ├── main.py                    # FastAPI app entry point
│   │   ├── config.py                  # Settings/environment
│   │   ├── database.py                # Async SQLAlchemy setup
│   │   ├── models/                    # SQLAlchemy ORM models
│   │   ├── schemas/                   # Pydantic request/response schemas
│   │   ├── routes/
│   │   │   ├── camera.py              # Camera configuration endpoints
│   │   │   ├── pipeline.py            # Pipeline control endpoints
│   │   │   ├── results.py             # ML results endpoints
│   │   │   ├── instances.py           # Pipeline instance CRUD
│   │   │   └── logs.py                # Activity log endpoints
│   │   ├── services/
│   │   │   ├── redis_service.py       # Async Redis client
│   │   │   └── activity_logger.py     # Centralized logging service
│   │   └── ws/
│   │       ├── feed.py                # Legacy video feed WebSocket
│   │       ├── results.py             # Legacy results WebSocket
│   │       ├── instance_feed.py       # Instance-specific feed WebSocket
│   │       └── instance_results.py    # Instance-specific results WebSocket
│   └── requirements.txt
├── ml_manager/
│   ├── manager/
│   │   ├── main.py                    # ML Manager entry point
│   │   ├── pipeline.py                # Pipeline DAG processing
│   │   ├── pipeline_manager.py        # Multi-pipeline orchestration
│   │   ├── camera_service.py          # Camera/video source handling
│   │   └── workers/                   # ML model workers
│   └── Dockerfile
├── frontend/
│   └── lib/
│       ├── main.dart                  # Flutter app entry point
│       ├── config/app_config.dart     # API/WS URL configuration
│       ├── screens/
│       │   ├── dashboard_screen.dart  # Main dashboard
│       │   ├── live_feed_screen.dart  # Single camera live feed
│       │   ├── settings_screen.dart   # Settings
│       │   ├── history_screen.dart    # Session history
│       │   └── multi_camera_grid.dart # Multi-camera grid view
│       └── services/
│           ├── api_service.dart       # REST API client
│           ├── websocket_service.dart # Legacy WebSocket client
│           └── multi_instance_ws_service.dart  # Multi-instance WS
├── database/
│   └── init.sql                       # Database schema initialization
├── docker-compose.yml
└── INSTRUCTIONS.md                    # This file
```

---

## Current Status & Goals
- **Date**: 2026-03-26
- **Current Work**: Feature 17 (Unlimited Camera Scalability)
- **Implementation Audit (Code-Verified)**: Features 1-16 are implemented except Feature 17, which remains in progress.
- **UI Audit Update (MCP)**: Completed deterministic per-page validation for Dashboard, Multi-Cam, Live Feed, Settings, and History via `?tab=` URLs.
- **Routing Reliability Update**: Frontend startup tab resolution now reads the actual browser location on web to ensure `?tab=...` opens the intended screen.

---

## Feature Implementation Progress

### ✅ Feature 1: Database Schema & Backend Models
- **Status**: Complete ✓ Verified
- **Files Modified**:
  - `database/init.sql` - Added 8 new tables with indexes
  - `backend/app/models/__init__.py` - Added 8 new SQLAlchemy models
  - `backend/app/schemas/__init__.py` - Added all Pydantic schemas
- **New Tables**: pipeline_instances, activity_logs, alert_rules, device_tokens, scheduled_jobs, webhooks, recordings, roi_zones
- **Verification**:
  ```bash
  docker compose exec database psql -U fyp_user -d fyp_database -c "\dt"
  # Should show 11 tables
  ```

### ✅ Feature 2: Multi-Pipeline ML Manager
- **Status**: Complete ✓ Verified
- **Files Created**:
  - `ml_manager/manager/pipeline_manager.py` - Multi-pipeline orchestration (600+ lines)
- **Files Modified**:
  - `ml_manager/manager/main.py` - Updated to use PipelineManager
  - `ml_manager/manager/workers/base_worker.py` - Added update_config() method
  - `ml_manager/manager/workers/yolo_worker.py` - Dynamic configuration support
- **Features**:
  - Manages multiple concurrent pipeline instances
  - Each instance has independent camera, models, and config
  - Instance-specific Redis channels: `pipeline:{instance_id}:results` and `pipeline:{instance_id}:frames`
  - Dynamic model configuration (enable/disable, adjust thresholds)
  - Accepts external instance_id from database (fixed 2026-03-25)

### ✅ Feature 3: Instance Management API
- **Status**: Complete ✓ Verified
- **Files Created**:
  - `backend/app/routes/instances.py` - Full CRUD API for pipeline instances
  - `backend/app/services/redis_service.py` - Redis client helper for async operations
- **API Endpoints**:
  ```
  POST   /api/instances/              - Create pipeline instance
  GET    /api/instances/              - List all instances
  GET    /api/instances/{id}          - Get specific instance
  PATCH  /api/instances/{id}          - Update instance name
  POST   /api/instances/{id}/control  - Control instance (start/stop/pause/resume)
  PATCH  /api/instances/{id}/models   - Update enabled models
  PATCH  /api/instances/{id}/config   - Update model configurations
  POST   /api/instances/import-batch  - Batch import camera+instance provisioning
  DELETE /api/instances/{id}          - Delete instance
  GET    /api/instances/{id}/status   - Get live Redis status
  ```
- **Testing**:
  ```bash
  # List instances
  curl http://localhost:8000/api/instances/

  # Start instance
  curl -X POST http://localhost:8000/api/instances/3/control \
    -H "Content-Type: application/json" \
    -d '{"action": "start"}'
  ```

### ✅ Feature 4: Activity Logging System
- **Status**: Complete ✓ Verified
- **Files Created**:
  - `backend/app/services/activity_logger.py` - Comprehensive logging service
  - `backend/app/routes/logs.py` - API endpoints for log querying
- **Files Modified**:
  - `backend/app/routes/instances.py` - Added logging to all CRUD operations
- **Features**:
  - Centralized logging with severity levels (debug, info, warning, error, critical)
  - Specialized logging methods for pipeline events
  - Real-time logging of all instance operations
- **API Endpoints**:
  ```
  GET    /api/logs/           - Query logs with filtering and pagination
  GET    /api/logs/statistics - Get log statistics and counts
  DELETE /api/logs/cleanup    - Cleanup old logs (7+ days)
  ```

### 🔄 Feature 5: Multi-Camera Grid UI
- **Status**: Complete ✓ Verified
- **Last Updated**: 2026-03-26

#### Files Created:
- `backend/app/ws/instance_feed.py` - Instance-specific video feed WebSocket handler
- `backend/app/ws/instance_results.py` - Instance-specific ML results WebSocket handler
- `frontend/lib/services/multi_instance_ws_service.dart` - Multi-instance WebSocket management
- `frontend/lib/screens/multi_camera_grid.dart` - Multi-camera grid UI component

#### Files Modified:
- `backend/app/main.py` - Added instance-specific WebSocket endpoints
- `frontend/lib/config/app_config.dart` - Added instance WebSocket URL methods
- `frontend/lib/services/api_service.dart` - Added complete instance management API
- `frontend/lib/main.dart` - Added Multi-Cam navigation and screen routing

#### Backend WebSocket Endpoints:
```
/ws/feed/{instance_id}     - Instance-specific video frames
/ws/results/{instance_id}  - Instance-specific ML results
```

#### Current Pipeline Instances:
| ID | Name | Status | Models |
|----|------|--------|--------|
| 1 | Camera 1 Instance | IDLE | yolo, pose |
| 3 | Test Logging Instance | RUNNING | yolo |
| 4 | Final Test Instance | IDLE | yolo, pose |
| 5 | Multi-Cam Test Instance | RUNNING | yolo |

#### Bug Fixes Applied (2026-03-25):
1. **Instance ID Mismatch Bug**: ML Manager was using internal ID counter instead of database instance_id
   - Fixed in `ml_manager/manager/pipeline_manager.py`: `create_instance()` now accepts external `instance_id`
   - ML Manager now uses the same instance_id as the database

2. **Instance Persistence Bug**: After ML Manager restart, instances weren't recreated
   - Fixed in `backend/app/routes/instances.py`: Start control action now sends `create_instance` command before `start`
   - Made `create_instance` idempotent (skips if instance already exists)

#### Frontend UI Features:
- Multi-camera grid with adaptive dynamic layout (no fixed preset camera limit)
- Individual instance tiles with:
  - Live video feed (Image.memory from base64 JPEG)
  - ML results overlay (toggleable)
  - Status indicator (green=running, red=stopped, orange=paused, blue=idle)
  - Control buttons (Start, Stop, Pause/Resume, Assign Models, Edit Camera, Delete, Overlay toggle)
- Empty-state Add Camera guidance (route user to Settings when no instances exist)
- Header-level Add Camera flow that creates camera config + pipeline instance in one action
- Group filter dropdown for large camera sets (All Groups + named groups)
- View modes: standard adaptive grid and grouped-section view
- Bulk controls for current group/filter and per-group section controls (Start/Stop/Pause/Resume Group)
- Search filter for camera name/group to manage large camera fleets quickly
- Status summary badges (running/paused/stopped/idle) for filtered set and grouped sections
- Collapsible group sections with expand/collapse all controls for lazy rendering at scale
- JSON import/export actions for bulk camera provisioning and migration workflows
- Import dry-run preview (create/skip summary and row-level reasons) before applying changes
- Import conflict mode: optional auto-rename on duplicate camera names
- Import conflict mode: optional merge-into-existing behavior for duplicate camera names
- Import progress dialog with live per-row status and progress bar
- Downloadable JSON export for browser-based file transfer/sharing
- Cancel action for long-running import operations
- Downloadable import execution report (JSON/CSV) for audit and troubleshooting
- On-screen import report viewer for immediate post-run analysis
- Backend batch import execution (single-request import path)
- Actionable batch-import failure messages (endpoint missing/server/network guidance)
- Instance count badge
- Refresh functionality

#### Runtime Verification (2026-03-26):
- Browser runtime checks against local backend confirmed active feed transport:
  - `GET /api/instances` returned running instances (`id=6`, `id=3`).
  - WebSocket `ws://localhost:8000/ws/feed/6` received frames (`messageCount=37`, first message in `60ms`).
  - WebSocket `ws://localhost:8000/ws/results/6` received results (`messageCount=36`, first message in `40ms`).
- Previously observed indefinite tile "Loading..." state is addressed by the new stale-feed watchdog and reconnect diagnostics.

#### Reliability Update (2026-03-26):
1. Added feed-health watchdog in `frontend/lib/screens/multi_camera_grid.dart`:
  - Periodic stale-feed detection for running instances.
  - Auto-triggered feed reconnect when no frames arrive within threshold.
2. Enhanced `frontend/lib/services/multi_instance_ws_service.dart` with:
  - Connection state tracking (`isFeedConnected`, last message timestamp, reconnect attempts).
  - Exponential reconnect backoff (2s, 4s, 8s) with per-instance reconnect timer guards.
  - Explicit `forceReconnectFeed()` for health-loop recovery.
3. Improved tile-level UX diagnostics for running cameras:
  - Replaced generic "Loading..." with state-aware text (`Waiting for frames`, `Reconnecting feed`, `Feed stale`).
  - Added retry-attempt indicator for easier troubleshooting.
4. Verification:
  - `flutter analyze lib/screens/multi_camera_grid.dart lib/services/multi_instance_ws_service.dart --no-fatal-infos` completed successfully for new logic.
  - Remaining analyzer infos are pre-existing `use_build_context_synchronously` warnings in older async dialog code paths.

#### Implementation Update (2026-03-25):
1. Removed fixed frontend grid presets as functional limit; grid now computes columns dynamically based on available width and instance count.
2. Added empty-state CTA to direct users to camera setup when no pipeline instances exist.
3. Added navigation bridge from Multi-Camera screen to Settings tab for faster camera onboarding flow.
4. Added direct Add Camera Instance dialog on Multi-Camera screen (name, optional group, source type/url, model selection).
5. Added per-instance model assignment dialog in camera tiles.
6. Added camera grouping/default assignment fields to backend camera config model/schema/API for persistence (`group_name`, `enabled_models`, `model_configs`).
7. Added camera metadata editing flow in camera tiles (rename, regroup, update source type/source URL).
8. Added group-based filtering for camera instances with clear no-results state when selected group has no instances.
9. Added grouped-section view mode for large deployments, with per-group quick controls.
10. Added bulk start/stop actions for currently filtered camera set.
11. Added bulk pause/resume actions for filtered and grouped camera control workflows.
12. Added per-camera delete flow from Multi-Cam UI (removes pipeline instance and linked camera configuration).
13. Added search filtering by camera name/group on top of group filter for high-volume camera management.
14. Added filtered no-results messaging for search context.
15. Added status summary badges in Multi-Cam header for faster operational visibility.
16. Added collapsible grouped sections and expand/collapse-all controls to reduce tile rendering load for large camera counts.
17. Added bulk JSON export to clipboard for current camera+instance configuration.
18. Added bulk JSON import dialog to provision many cameras/instances in one operation (with duplicate-name skipping and result summary).
19. Added import preview mode to validate payloads and show per-row create/skip reasons before import.
20. Added optional rename-on-conflict mode for bulk imports (auto-generates unique camera names).
21. Added live import progress dialog with progress bar and row-level status updates during provisioning.
22. Added downloadable JSON export in browser (file download) in addition to clipboard export.
23. Added import cancellation control for long-running batch imports.
24. Added merge-on-conflict import strategy to update existing camera+instance metadata/config when duplicate names are provided.
25. Added persisted import execution report with row-level outcomes and downloadable JSON/CSV exports.
26. Added in-app report viewer for the latest import execution (summary + row details).
27. Added backend batch import endpoint and frontend single-request import integration.
28. Removed legacy frontend row-by-row import fallback to enforce backend-only batch execution.
29. Added actionable backend-only import error guidance (404/5xx/network cases).

#### Testing Commands:
```bash
# Check ML Manager received commands
docker compose logs --tail=30 ml_manager

# Check WebSocket connections
docker compose logs --tail=30 backend | grep WebSocket

# Start an instance
curl -X POST http://localhost:8000/api/instances/3/control \
  -H "Content-Type: application/json" \
  -d '{"action":"start"}'

# Check instance status from Redis
docker compose exec redis redis-cli HGETALL pipeline:3:status
```

---

## Pending Features (TODO)

### Feature 6: Dashboard Analytics Charts
- **Status**: Complete (Implemented 2026-03-26)
- **Description**: Add real-time analytics charts to dashboard
- **Components**: Detection counts, FPS graphs, model performance metrics
- **Implementation**:
  - Updated `frontend/lib/screens/dashboard.dart` with a realtime analytics section.
  - Added FPS sparkline chart using rolling history from periodic pipeline status refresh.
  - Added instance status distribution chart (running/paused/stopped/idle) from `/api/instances/`.
  - Added detection count and average model latency charts from `/api/results/session/{id}/stats` when active session exists.
- **Verification**:
  - `flutter analyze lib/screens/dashboard.dart --no-fatal-infos` (no errors/warnings, one existing deprecation info).
  - VS Code diagnostics for `dashboard.dart`: no errors.

### Feature 7: Model Configuration UI
- **Status**: Complete (Implemented 2026-03-26)
- **Description**: UI for configuring model parameters per instance
- **Components**: Confidence thresholds, target classes, NMS settings
- **Implementation**:
  - Added per-instance model parameter dialog in `frontend/lib/screens/multi_camera_grid.dart`.
  - Added editable model settings per enabled model: confidence threshold, NMS threshold, and target classes.
  - Persisted updates through existing backend APIs:
    - `PATCH /api/instances/{id}/config`
    - `PATCH /api/camera/configs/{config_id}` (to keep camera defaults aligned)
- **Verification**:
  - `flutter analyze lib/screens/multi_camera_grid.dart --no-fatal-infos` (no errors/warnings; info-level lints only).
  - VS Code diagnostics for `multi_camera_grid.dart`: no errors.

### Feature 8: Alert/Trigger System
- **Status**: Complete ✓ Verified (Implemented 2026-03-26)
- **Description**: Configurable alert rules based on detection events
- **Implementation**:
  - Added backend alert-rule API route module: `backend/app/routes/alerts.py`.
  - Added backend CRUD endpoints:
    - `GET /api/alerts/`
    - `POST /api/alerts/`
    - `GET /api/alerts/{id}`
    - `PATCH /api/alerts/{id}`
    - `DELETE /api/alerts/{id}`
  - Wired alert routes into FastAPI app bootstrap in `backend/app/main.py`.
  - Added frontend API client methods in `frontend/lib/services/api_service.dart`.
  - Added Settings UI alert management section in `frontend/lib/screens/settings.dart`:
    - List rules
    - Create rule dialog (trigger type/classes/confidence/count/cooldown)
    - Toggle rule active state
    - Delete rule
- **Verification (2026-03-26)**:
  - VS Code diagnostics: no errors in modified backend/frontend files.
  - `flutter analyze lib/screens/settings.dart --no-fatal-infos`: no issues.
  - Chrome MCP end-to-end API test passed for create/list/update/delete:
    - create `201`, list `200`, patch `200`, delete `204`, and deleted rule absent from subsequent list.

### Feature 9: Recording Feature
- **Status**: Complete ✓ Verified (Implemented 2026-03-26)
- **Description**: Record video segments with ML annotations
- **Implementation**:
  - Added backend recording lifecycle route module: `backend/app/routes/recordings.py`.
  - Added endpoints:
    - `GET /api/recordings/`
    - `GET /api/recordings/{id}`
    - `POST /api/recordings/` (start recording metadata + control command)
    - `POST /api/recordings/{id}/stop` (stop and finalize metadata)
    - `DELETE /api/recordings/{id}`
  - Added recording stop schema `RecordingStopRequest` in `backend/app/schemas/__init__.py`.
  - Wired route in FastAPI app startup (`backend/app/main.py`).
  - Added frontend API client methods in `frontend/lib/services/api_service.dart`.
  - Implemented ML manager recording writer lifecycle in `ml_manager/manager/pipeline_manager.py`:
    - start writer on `start_recording`
    - write frames during processing loop
    - finalize writer and publish recording metadata on `stop_recording`
  - Updated ML manager video volume to writable in `docker-compose.yml` (`./videos:/videos`).
  - Added startup DB compatibility migration in `backend/app/database.py` for existing deployments missing newer `camera_configs` columns (`group_name`, `enabled_models`, `model_configs`).
  - Hardened instance control error handling in `backend/app/routes/instances.py` with transaction rollback before error logging.
- **Verification (2026-03-26)**:
  - VS Code diagnostics: no errors in modified backend files.
  - Chrome MCP end-to-end recording test passed on a recreated instance with video file source:
    - instance create `201`, instance start `202`
    - recording start `201`, recording stop `200`
    - finalized metadata persisted (`file_size_bytes`, `duration_seconds`, `fps`, `width`, `height`, `codec`, `frame_count`)
  - File-system validation in container passed:
    - `/videos/recordings/recording_e2e_1774472110149.mp4` exists with non-zero size.
- **Known Limitation**:
  - `results_file_path` annotation export is still not populated yet (belongs to Feature 11 export/annotation workstream).

### Feature 10: Playback Controls UI
- **Status**: Complete ✓ Verified (Implemented 2026-03-26)
- **Description**: UI for video playback with seek, speed controls
- **Implementation**:
  - Added backend recording stream endpoint in `backend/app/routes/recordings.py`:
    - `GET /api/recordings/{id}/stream` (safe file serving for in-app playback)
  - Added frontend playback dependency in `frontend/pubspec.yaml`:
    - `video_player`
  - Extended History screen in `frontend/lib/screens/history.dart`:
    - Added segmented view: Sessions / Recordings
    - Added recordings list cards with duration/size/codec metadata
    - Added player dialog with:
      - play/pause controls
      - seek/scrub via progress bar + timeline labels (current and total time)
      - skip backward/forward 10 seconds controls
      - keyboard shortcuts: Space (play/pause), Left/J (-10s), Right/L (+10s)
      - playback speed selector (0.5x, 1.0x, 1.5x, 2.0x)
- **Verification (2026-03-26)**:
  - `flutter analyze lib/screens/history.dart --no-fatal-infos` passed.
  - `flutter build web --release` passed.
  - Backend route compiles with no diagnostics errors.

### Feature 11: Export Functionality
- **Status**: Complete ✓ Verified (Implemented 2026-03-26)
- **Description**: Export results as CSV, JSON, or video files
- **Implementation**:
  - Backend export endpoints for session detection results in `backend/app/routes/results.py`:
    - `GET /api/results/session/{session_id}/export/json`
    - `GET /api/results/session/{session_id}/export/csv`
  - Backend export endpoints for recording metadata/files in `backend/app/routes/recordings.py`:
    - `GET /api/recordings/{recording_id}/export/json`
    - `GET /api/recordings/{recording_id}/export/csv`
    - `GET /api/recordings/{recording_id}/download`
  - Frontend export actions in `frontend/lib/screens/history.dart`:
    - Session card export menu (Results JSON/CSV)
    - Recording action sheet (Download Video, Export JSON Metadata, Export CSV Metadata)
  - Added frontend dependency in `frontend/pubspec.yaml`:
    - `url_launcher`
- **Verification (2026-03-26)**:
  - `flutter analyze lib/screens/history.dart --no-fatal-infos`: passed.
  - `flutter build web --release`: passed.
  - Chrome MCP API verification passed:
    - Session exports: JSON `200`, CSV `200` with attachment header
    - Recording exports: JSON `200`, CSV `200` with attachment header, Video download `200`

### Feature 12: Push Notifications (FCM)
- **Status**: Complete ✓ Verified (Implemented 2026-03-26)
- **Description**: Firebase Cloud Messaging for mobile alerts
- **Implementation**:
  - Added backend push notification routes in `backend/app/routes/notifications.py`:
    - `GET /api/notifications/devices` (list registered tokens)
    - `POST /api/notifications/devices` (register/upsert token)
    - `PATCH /api/notifications/devices/{id}` (activate/deactivate/update metadata)
    - `DELETE /api/notifications/devices/{id}`
    - `POST /api/notifications/test` (test dispatch in simulation mode)
  - Added notification schemas in `backend/app/schemas/__init__.py`:
    - `DeviceTokenUpdate`
    - `PushNotificationTestRequest`
    - `PushNotificationTestResponse`
  - Wired notifications router in `backend/app/main.py`.
  - Added frontend API methods in `frontend/lib/services/api_service.dart` for token CRUD and test dispatch.
  - Added Settings UI Push Notifications section in `frontend/lib/screens/settings.dart`:
    - Register token form (platform/token/device/user)
    - Device token list with active toggle + delete
    - Test notification form and dispatch action
- **Verification (2026-03-26)**:
  - `flutter analyze lib/screens/settings.dart --no-fatal-infos`: passed.
  - `flutter build web --release`: passed.
  - Chrome MCP API lifecycle test passed:
    - register `201`, list `200`, patch `200`, test `200`, delete `204`.
  - Active-token test dispatch validated:
    - `POST /api/notifications/test` returned `sent_to: 1` and `simulated: true` with active token.
- **Note**:
  - Current dispatch is simulation mode for environment-safe verification.
  - Real delivery requires FCM/APNS provider credentials and transport integration.

### Feature 13: Webhook System
- **Status**: Complete ✓ Verified (Implemented 2026-03-26)
- **Description**: HTTP webhooks for third-party integrations
- **Implementation**:
  - Added backend webhook routes in `backend/app/routes/webhooks.py`:
    - `GET /api/webhooks/`
    - `POST /api/webhooks/`
    - `PATCH /api/webhooks/{id}`
    - `DELETE /api/webhooks/{id}`
    - `POST /api/webhooks/test`
  - Added webhook route registration in `backend/app/main.py`.
  - Implemented outbound JSON POST test delivery with optional HMAC signature header (`X-FYP-Signature`) and retry handling.
  - Added frontend webhook API client methods in `frontend/lib/services/api_service.dart`.
  - Added Settings UI webhook management section in `frontend/lib/screens/settings.dart`:
    - Create webhook form (name/url/secret/events)
    - Webhook list with active toggle, test action, delete action
    - Last status visibility from backend metadata
- **Verification (2026-03-26)**:
  - `flutter analyze lib/screens/settings.dart --no-fatal-infos`: passed.
  - `flutter build web --release`: passed.
  - Chrome MCP API lifecycle + delivery test passed:
    - create `201`, list `200`, test `200`, patch `200`, delete `204`
    - outbound test delivery confirmed (`status_code: 200`) using `https://httpbin.org/post`.

### Feature 14: Scheduled Pipelines
- **Status**: Complete ✓ Verified (Implemented 2026-03-26)
- **Description**: Schedule pipeline start/stop at specific times
- **Tables Ready**: scheduled_jobs (created in Feature 1)
- **Implementation (Current Slice)**:
  - Added backend schedule routes in `backend/app/routes/schedules.py`:
    - `GET /api/schedules/`
    - `POST /api/schedules/`
    - `PATCH /api/schedules/{id}`
    - `DELETE /api/schedules/{id}`
    - `POST /api/schedules/{id}/run` (manual trigger for verification)
  - Wired schedules router in `backend/app/main.py`.
  - Added frontend schedule API client methods in `frontend/lib/services/api_service.dart`.
  - Added Settings UI schedule management section in `frontend/lib/screens/settings.dart`:
    - Create schedule form (camera/models/cron/duration)
    - Schedule list with active toggle, manual run action, delete action
  - Added backend runtime scheduler service in `backend/app/services/schedule_service.py`:
    - Background polling loop for active scheduled jobs
    - Cron evaluation via `croniter`
    - Automatic pipeline start trigger at due times
    - Optional auto-stop based on `duration_minutes`
    - Next run computation and job status tracking
  - Wired scheduler startup/shutdown in app lifespan (`backend/app/main.py`).
  - Added backend dependency `croniter` in `backend/requirements.txt`.
- **Verification (2026-03-26)**:
  - `flutter analyze lib/screens/settings.dart --no-fatal-infos`: passed.
  - `flutter build web --release`: passed.
  - Chrome MCP API lifecycle test passed:
    - create `201`, list `200`, manual run `200`, patch `200`, delete `204`.
    - manual run updates `last_run_status` to `manual_triggered`.
  - Automatic trigger verification passed:
    - Created active schedule, waited for scheduler poll, observed `last_run_status: started` and populated `next_run_at`.

### Feature 15: ROI Editor (Optional)
- **Status**: Complete ✓ Verified (Implemented 2026-03-26)
- **Description**: Region of Interest drawing tool
- **Tables Ready**: roi_zones (created in Feature 1)
- **Implementation**:
  - Added backend ROI management router `backend/app/routes/roi.py`:
    - `GET /api/roi/zones` (camera filter + include_inactive)
    - `POST /api/roi/zones`
    - `PATCH /api/roi/zones/{zone_id}`
    - `DELETE /api/roi/zones/{zone_id}`
  - Registered ROI router in `backend/app/main.py`.
  - Added frontend ROI API methods in `frontend/lib/services/api_service.dart`.
  - Added ROI Editor section in `frontend/lib/screens/settings.dart`:
    - Camera-scoped ROI list
    - Polygon drawing canvas with click-to-add points
    - Undo/clear draft controls
    - Create/update/delete/toggle ROI actions
- **Verification (2026-03-26)**:
  - IDE diagnostics check: no errors in modified backend/frontend files.
  - Chrome MCP ROI API lifecycle test passed:
    - create `201`, list `200`, patch `200`, delete `204`.

### Feature 16: Activity Log Viewer UI
- **Status**: Complete ✓ Verified (Implemented 2026-03-26)
- **Description**: Frontend UI for viewing activity logs
- **Backend Ready**: /api/logs/ endpoints (Feature 4)
- **Implementation**:
  - Added activity log API methods in `frontend/lib/services/api_service.dart`:
    - `getActivityLogs`
    - `getRecentErrors`
    - `getLogStatistics`
  - Added Settings UI Activity Logs section in `frontend/lib/screens/settings.dart`:
    - Severity filter
    - Adjustable result limit
    - 24-hour statistics chips (total/errors/critical/warnings)
    - Recent activity list with severity badges
  - Fixed backend log service time-window bug in `backend/app/services/activity_logger.py` affecting `recent-errors` endpoint.
- **Verification (2026-03-26)**:
  - `flutter analyze lib/screens/settings.dart --no-fatal-infos`: passed.
  - `flutter build web --release`: passed.
  - Chrome MCP API checks passed:
    - `/api/logs/statistics` `200`
    - `/api/logs/` `200`
    - `/api/logs/recent-errors` `200`.

### Feature 17: Unlimited Camera Scalability & Camera Management UX
- **Status**: In Progress (Milestone 22 complete)
- **Description**: Support arbitrary number of user-entered cameras and dynamic UI rendering without fixed camera/input presets
- **Requirements**:
  - No fixed camera count limit in UI rendering
  - Empty-state guidance with Add Camera action
  - Per-camera tool/model/pipeline assignment
  - Persistence of camera configurations for quick restart
  - Camera naming and grouping support
- **Progress (2026-03-25)**:
  - Dynamic adaptive camera rendering completed
  - Add Camera creation flow implemented in Multi-Camera UI
  - Per-instance model assignment UI implemented
  - Backend camera config now supports persisted group/default assignment fields
  - Group filtering and camera metadata editing implemented in Multi-Camera UI
  - Grouped-section view and bulk group controls implemented
  - Lifecycle controls extended with pause/resume (single, filtered set, and grouped sections)
  - Camera+instance deletion flow added for high-volume lifecycle management
  - Name/group search filtering added for fast large-scale camera lookup
  - Status summary and lazy grouped rendering controls added for better high-scale operability
  - Bulk JSON import/export flow added for rapid camera fleet provisioning
  - Dry-run import preview added to reduce provisioning errors at scale
  - Conflict-resolution and live progress feedback added for safer large-batch imports
  - Downloadable export and cancellable import flows added for operational reliability
  - Merge-on-conflict strategy added for idempotent bulk reconfiguration workflows
  - Import report exports (JSON/CSV) added for operational auditability
  - In-app report inspection and import attempt telemetry added for safer high-volume import runs
  - Strict fail-fast import mode and retry-attempt telemetry added for controllable/traceable large-batch provisioning
  - Backend batch import endpoint added with strict/tolerant execution modes for single-request provisioning
  - Frontend import flow switched to backend-only batch mode (legacy row-by-row fallback removed for strict endpoint reliance)
  - Backend-only import failure UX improved with actionable endpoint/network/server error messages for faster operator recovery
- **Progress (2026-03-26)**:
  - Added backend paginated listing endpoint `GET /api/instances/paged?limit=&offset=&status_filter=` for large camera fleets.
  - Updated frontend API service with `getInstancesPaged()`.
  - Multi-Camera UI now loads instances in pages (initial page + "Load More" incremental fetch), reducing initial payload/WS subscription burst for large deployments.
  - Header instance counter now shows loaded vs total counts to make pagination state explicit.
  - Added server-side filter support on paged endpoint (`group_name`, `search_query`) to avoid expensive client-side filtering on large fleets.
  - Multi-Camera UI search/group controls now trigger paged backend reloads (debounced search) instead of filtering only in-memory tiles.
  - Added server-side sort support on paged endpoint (`sort_by`, `sort_order`) with sortable fields: `created_at`, `name`, `status`, `camera_name`, `group_name`.
  - Added Multi-Camera sort controls (Sort By + Order) wired to backend paged reloads.
  - Added grouped-view progressive tile windowing in Multi-Camera UI:
    - Per-group render window starts with chunked tile count.
    - "Load More Tiles" expands group rendering incrementally.
    - Expand-all and per-group expand now reset to chunk baseline to avoid rendering all tiles at once.

- **Verification (2026-03-26)**:
  - `flutter analyze lib/screens/multi_camera_grid.dart lib/services/api_service.dart --no-fatal-infos`: passed for new pagination logic (remaining `use_build_context_synchronously` infos are pre-existing).
  - Browser endpoint checks:
    - `/api/instances/paged?limit=2&offset=0` returned 2 items with `total=4`.
    - `/api/instances/paged?limit=2&offset=2` returned next 2 items with `total=4`.
    - `/api/instances/paged?limit=10&offset=0&status_filter=running&search_query=zzzz-not-found` returned `items=[]`, `total=0` (filter path validated).
    - `/api/instances/paged?limit=4&offset=0&sort_by=name&sort_order=asc` returned names in ascending order (`Camera 1`, `Final`, `Recording`, `Test`).
    - `/api/instances/paged?limit=4&offset=0&sort_by=name&sort_order=desc` returned names in descending order (`Test`, `Recording`, `Final`, `Camera 1`).
  - `flutter analyze lib/screens/multi_camera_grid.dart --no-fatal-infos`: passed for grouped windowing changes (remaining `use_build_context_synchronously` infos are pre-existing).

### Verification Note (Environment)
- API command automation for scale benchmark runs is currently restricted by terminal policy for REST command execution in this session; UI/runtime validations continue through Chrome MCP and in-app diagnostics.

---

## Quick Reference Commands

### Docker Management
```bash
# Start all services
.\commandScripts\start.bat

# Rebuild and start
.\commandScripts\start.bat rebuild

# Stop all services
.\commandScripts\stop.bat

# View logs
docker compose logs -f backend
docker compose logs -f ml_manager
docker compose logs -f frontend

# Restart specific service
docker compose restart backend
docker compose restart ml_manager

# Rebuild specific service
docker compose build --no-cache frontend
docker compose up -d frontend
```

### Database Operations
```bash
# Connect to database
docker compose exec database psql -U fyp_user -d fyp_database

# List tables
\dt

# Query instances
SELECT id, name, status, enabled_models FROM pipeline_instances;

# Query activity logs
SELECT event_type, severity, message FROM activity_logs ORDER BY created_at DESC LIMIT 10;
```

### Redis Operations
```bash
# Check pub/sub channels
docker compose exec redis redis-cli PUBSUB CHANNELS "pipeline:*"

# Get manager status
docker compose exec redis redis-cli HGETALL pipeline:manager:status

# Get instance status
docker compose exec redis redis-cli HGETALL pipeline:3:status

# Subscribe to instance frames (for debugging)
docker compose exec redis redis-cli SUBSCRIBE "pipeline:3:frames"
```

### API Testing
```bash
# Health check
curl http://localhost:8000/health

# List instances
curl http://localhost:8000/api/instances/

# Start instance
curl -X POST http://localhost:8000/api/instances/3/control \
  -H "Content-Type: application/json" \
  -d '{"action":"start"}'

# Stop instance
curl -X POST http://localhost:8000/api/instances/3/control \
  -H "Content-Type: application/json" \
  -d '{"action":"stop"}'

# View logs
curl http://localhost:8000/api/logs/

# Log statistics
curl http://localhost:8000/api/logs/statistics
```

### Flutter Development
```bash
cd frontend
flutter clean
flutter pub get
flutter build web --release
```

---

## Development Notes

### Code Patterns Used
- **Async/Await**: All database and Redis operations use async patterns
- **Pydantic Schemas**: Request/response validation with ConfigDict
- **SQLAlchemy ORM**: Async sessions with proper relationship loading
- **Redis Pub/Sub**: Commands sent via `pipeline:control` channel
- **WebSocket**: Instance-specific channels for real-time data

### Important Fixes Applied
1. **Pydantic V2 Migration**: Changed `class Config` to `model_config = ConfigDict`
2. **SQLAlchemy JSON Update**: Use `flag_modified()` for JSON field updates
3. **Redis Async**: Using `redis.asyncio` (aioredis) for non-blocking operations
4. **Flutter AppColors**: Replaced custom `AppColors.info` with `Colors.blue`
5. **Instance ID Sync**: ML Manager now uses database instance_id

### Preferences
- Implement features one at a time, testing thoroughly before moving on
- Use descriptive variable names and comments
- Follow existing code patterns in the project
- Test both backend API and frontend UI after changes
