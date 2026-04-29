"""
Results retrieval routes
"""

import csv
import io
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse, StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models import DetectionResult
from app.schemas import DetectionResultResponse

router = APIRouter(prefix="/api/results", tags=["Results"])


@router.get("/session/{session_id}", response_model=list[DetectionResultResponse])
async def get_session_results(
    session_id: int,
    model_name: str = Query(None, description="Filter by model name"),
    limit: int = Query(100, le=1000),
    offset: int = 0,
    db: AsyncSession = Depends(get_db)
):
    """Get detection results for a session."""
    query = select(DetectionResult).where(DetectionResult.session_id == session_id)

    if model_name:
        query = query.where(DetectionResult.model_name == model_name)

    query = query.order_by(DetectionResult.frame_id.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    return result.scalars().all()


@router.get("/session/{session_id}/frame/{frame_id}")
async def get_frame_results(
    session_id: int,
    frame_id: int,
    db: AsyncSession = Depends(get_db)
):
    """Get all model results for a specific frame."""
    result = await db.execute(
        select(DetectionResult).where(
            DetectionResult.session_id == session_id,
            DetectionResult.frame_id == frame_id,
        )
    )
    results = result.scalars().all()

    if not results:
        raise HTTPException(status_code=404, detail="No results found for this frame")

    return {
        "frame_id": frame_id,
        "session_id": session_id,
        "results": {r.model_name: r.result_data for r in results},
        "total_processing_time_ms": sum(r.processing_time_ms or 0 for r in results),
    }


@router.get("/session/{session_id}/stats")
async def get_session_stats(
    session_id: int,
    db: AsyncSession = Depends(get_db)
):
    """Get summary statistics for a session."""
    result = await db.execute(
        select(
            DetectionResult.model_name,
            func.count(DetectionResult.id).label("count"),
            func.avg(DetectionResult.confidence).label("avg_confidence"),
            func.avg(DetectionResult.processing_time_ms).label("avg_processing_time_ms"),
        )
        .where(DetectionResult.session_id == session_id)
        .group_by(DetectionResult.model_name)
    )
    stats = result.all()

    return {
        "session_id": session_id,
        "models": [
            {
                "model_name": s.model_name,
                "total_detections": s.count,
                "avg_confidence": round(s.avg_confidence, 4) if s.avg_confidence else None,
                "avg_processing_time_ms": round(s.avg_processing_time_ms, 2) if s.avg_processing_time_ms else None,
            }
            for s in stats
        ],
    }


@router.get("/session/{session_id}/export/json")
async def export_session_results_json(
    session_id: int,
    model_name: str = Query(None, description="Filter by model name"),
    db: AsyncSession = Depends(get_db),
):
    """Export detection results for a session as JSON."""
    query = select(DetectionResult).where(DetectionResult.session_id == session_id)
    if model_name:
        query = query.where(DetectionResult.model_name == model_name)
    query = query.order_by(DetectionResult.frame_id.asc(), DetectionResult.id.asc())

    result = await db.execute(query)
    rows = result.scalars().all()

    payload = [
        {
            "id": row.id,
            "session_id": row.session_id,
            "frame_id": row.frame_id,
            "timestamp": row.timestamp.isoformat() if row.timestamp else None,
            "model_name": row.model_name,
            "result_data": row.result_data,
            "confidence": row.confidence,
            "processing_time_ms": row.processing_time_ms,
        }
        for row in rows
    ]

    return JSONResponse(content=payload)


@router.get("/session/{session_id}/export/csv")
async def export_session_results_csv(
    session_id: int,
    model_name: str = Query(None, description="Filter by model name"),
    db: AsyncSession = Depends(get_db),
):
    """Export detection results for a session as CSV."""
    query = select(DetectionResult).where(DetectionResult.session_id == session_id)
    if model_name:
        query = query.where(DetectionResult.model_name == model_name)
    query = query.order_by(DetectionResult.frame_id.asc(), DetectionResult.id.asc())

    result = await db.execute(query)
    rows = result.scalars().all()

    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow([
        "id",
        "session_id",
        "frame_id",
        "timestamp",
        "model_name",
        "confidence",
        "processing_time_ms",
        "result_data_json",
    ])

    for row in rows:
        writer.writerow([
            row.id,
            row.session_id,
            row.frame_id,
            row.timestamp.isoformat() if row.timestamp else "",
            row.model_name,
            row.confidence,
            row.processing_time_ms,
            row.result_data,
        ])

    csv_data = buffer.getvalue()
    buffer.close()

    return StreamingResponse(
        iter([csv_data]),
        media_type="text/csv",
        headers={
            "Content-Disposition": f"attachment; filename=session_{session_id}_results.csv",
        },
    )
