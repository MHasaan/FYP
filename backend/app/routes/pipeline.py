"""
ML Pipeline control routes
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import Session
from app.schemas import (
    SessionCreate, SessionResponse,
    PipelineStatusResponse, PipelineControlRequest
)
from app.services.pipeline_service import PipelineService

router = APIRouter(prefix="/api/pipeline", tags=["Pipeline"])


@router.get("/status", response_model=PipelineStatusResponse)
async def get_pipeline_status():
    """Get current pipeline status."""
    async with PipelineService() as service:
        return await service.get_status()


@router.post("/control")
async def control_pipeline(
    request: PipelineControlRequest,
    db: AsyncSession = Depends(get_db)
):
    """Start, stop, pause, or resume the ML pipeline."""
    async with PipelineService() as service:
        if request.action == "start":
            if not request.camera_source:
                raise HTTPException(status_code=400, detail="camera_source required to start pipeline")

            # Create a new session
            session = Session(
                name=f"Session {request.camera_source}",
                camera_source=request.camera_source,
                status="running",
                config=request.config,
            )
            db.add(session)

            try:
                await db.commit()
                await db.refresh(session)

                result = await service.start(
                    session_id=session.id,
                    camera_source=request.camera_source,
                    config=request.config,
                )

                # Check if start command failed
                if result.get("error"):
                    # Rollback session status
                    session.status = "failed"
                    await db.commit()
                    raise HTTPException(status_code=500, detail=result["message"])

                return {"status": "started", "session_id": session.id, **result}
            except HTTPException:
                raise
            except Exception as e:
                await db.rollback()
                raise HTTPException(status_code=500, detail=f"Failed to start pipeline: {e}")

        elif request.action == "stop":
            result = await service.stop()
            return {"status": "stopped", **result}

        elif request.action == "pause":
            result = await service.pause()
            return {"status": "paused", **result}

        elif request.action == "resume":
            result = await service.resume()
            return {"status": "resumed", **result}

        else:
            raise HTTPException(status_code=400, detail=f"Unknown action: {request.action}")


# ============ Session Management ============

@router.get("/sessions", response_model=list[SessionResponse])
async def list_sessions(
    limit: int = 20,
    offset: int = 0,
    db: AsyncSession = Depends(get_db)
):
    """List all sessions."""
    result = await db.execute(
        select(Session).order_by(Session.created_at.desc()).limit(limit).offset(offset)
    )
    return result.scalars().all()


@router.get("/sessions/{session_id}", response_model=SessionResponse)
async def get_session(session_id: int, db: AsyncSession = Depends(get_db)):
    """Get a specific session."""
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return session
