"""
FYP Backend - FastAPI Application Entry Point
"""

from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import get_settings
from app.database import init_db
from app.routes import (
    alerts,
    auth,
    camera,
    detection_settings,
    incidents,
    instances,
    logs,
    notifications,
    patients,
    pipeline,
    recordings,
    reports,
    results,
    roi,
    schedules,
    system,
    webhooks,
)
from app.ws.feed import feed_websocket
from app.ws.results import results_websocket
from app.ws.instance_feed import instance_feed_websocket
from app.ws.instance_results import instance_results_websocket
from app.services.redis_service import close_redis_client
from app.services.schedule_service import ScheduleRunnerService
from app.services.result_processor import ResultProcessor

settings = get_settings()
schedule_runner = ScheduleRunnerService()
result_processor = ResultProcessor()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events."""
    # Startup
    print("Starting FYP Backend...")
    await init_db()
    print("Database initialized")
    await schedule_runner.start()
    print("Schedule runner started")
    await result_processor.start()
    print("Result processor started")
    yield
    # Shutdown
    print("Shutting down FYP Backend...")
    await schedule_runner.stop()
    print("Schedule runner stopped")
    await result_processor.stop()
    print("Result processor stopped")
    await close_redis_client()
    print("Redis client closed")


app = FastAPI(
    title="FYP ML Pipeline Backend",
    description="Backend API for the real-time ML pipeline system",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS - use environment-configured origins
cors_origins = [origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()]
if not cors_origins:
    # Default to restrictive CORS in production (only localhost for development)
    cors_origins = ["http://localhost:3000", "http://localhost:8080"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============ API Key Authentication Middleware ============
@app.middleware("http")
async def verify_api_key(request: Request, call_next):
    """Verify API key for protected endpoints."""
    # Skip auth for public endpoints
    public_paths = ["/health", "/", "/docs", "/openapi.json", "/redoc"]
    public_prefixes = ["/api/auth/login", "/api/auth/register"]
    if (
        request.url.path in public_paths
        or request.url.path.startswith("/docs")
        or any(request.url.path.startswith(prefix) for prefix in public_prefixes)
    ):
        return await call_next(request)

    # Skip auth for WebSocket upgrade requests (handled separately)
    if request.headers.get("upgrade", "").lower() == "websocket":
        return await call_next(request)

    # If API key is configured, enforce it
    if settings.api_key:
        api_key = request.headers.get("X-API-Key")
        if api_key != settings.api_key:
            return JSONResponse(
                status_code=401,
                content={"detail": "Invalid or missing API key"}
            )

    return await call_next(request)


# ============ REST Routes ============
app.include_router(camera.router)
app.include_router(auth.router)
app.include_router(patients.router)
app.include_router(incidents.router)
app.include_router(detection_settings.router)
app.include_router(reports.router)
app.include_router(system.router)
app.include_router(pipeline.router)
app.include_router(results.router)
app.include_router(instances.router)
app.include_router(logs.router)
app.include_router(alerts.router)
app.include_router(recordings.router)
app.include_router(notifications.router)
app.include_router(webhooks.router)
app.include_router(schedules.router)
app.include_router(roi.router)


# ============ WebSocket Endpoints ============
@app.websocket("/ws/feed")
async def ws_feed(websocket: WebSocket):
    """Live video feed WebSocket."""
    await feed_websocket(websocket)


@app.websocket("/ws/results")
async def ws_results(websocket: WebSocket):
    """Real-time ML results WebSocket."""
    await results_websocket(websocket)


@app.websocket("/ws/feed/{instance_id}")
async def ws_instance_feed(websocket: WebSocket, instance_id: int):
    """Instance-specific video feed WebSocket."""
    await instance_feed_websocket(websocket, instance_id)


@app.websocket("/ws/results/{instance_id}")
async def ws_instance_results(websocket: WebSocket, instance_id: int):
    """Instance-specific ML results WebSocket."""
    await instance_results_websocket(websocket, instance_id)


# ============ Health Check ============
@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "ok",
        "version": "1.0.0",
        "services": {
            "backend": "running",
        },
    }


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "name": "FYP ML Pipeline Backend",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health",
    }
