"""
Pipeline Instance Management Routes

CRUD operations for managing ML pipeline instances.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, delete, func, or_
from datetime import datetime, timezone
from typing import Any, List
import json

from app.database import get_db
from app.models import PipelineInstance, CameraConfig, Session as DBSession
from app.schemas import (
    PipelineInstanceCreate,
    PipelineInstanceUpdate,
    PipelineInstanceResponse,
    PipelineInstanceControl,
    PipelineInstanceModelsUpdate,
    PipelineInstanceConfigUpdate,
    PipelineInstanceBatchImportRequest,
    PipelineInstanceBatchImportResponse,
)
from app.services.redis_service import get_redis_client
from app.services.activity_logger import ActivityLogger


router = APIRouter(prefix="/api/instances", tags=["Pipeline Instances"])


def _normalize_batch_camera_row(camera: Any) -> dict[str, Any] | None:
    if not isinstance(camera, dict):
        return None

    name = str(camera.get("name", "")).strip()
    source_type = str(camera.get("source_type", "")).strip()
    source_url = str(camera.get("source_url", "")).strip()
    if not name or not source_type or not source_url:
        return None

    enabled_models = camera.get("enabled_models") or []
    if not isinstance(enabled_models, list):
        enabled_models = []
    enabled_models = [str(m) for m in enabled_models]

    model_configs = camera.get("model_configs") or {}
    if not isinstance(model_configs, dict):
        model_configs = {}

    group_name = camera.get("group_name")
    if group_name is not None:
        group_name = str(group_name).strip() or None

    return {
        "name": name,
        "source_type": source_type,
        "source_url": source_url,
        "group_name": group_name,
        "enabled_models": enabled_models,
        "model_configs": model_configs,
    }


def _generate_unique_camera_name(base_name: str, used_lower_names: set[str]) -> str:
    candidate = base_name
    suffix = 1
    while candidate.lower() in used_lower_names:
        candidate = f"{base_name} ({suffix})"
        suffix += 1
    return candidate


@router.post("/import-batch", response_model=PipelineInstanceBatchImportResponse)
async def import_pipeline_instances_batch(
    payload: PipelineInstanceBatchImportRequest,
    db: AsyncSession = Depends(get_db),
):
    """Import many camera+instance definitions in one backend request."""
    mode = payload.mode
    strict_mode = mode == "strict"
    conflict_strategy = payload.conflict_strategy

    report_rows: list[dict[str, Any]] = []
    created_count = 0
    renamed_count = 0
    merged_count = 0
    skipped_count = 0
    processed_count = 0
    strict_aborted = False

    cameras_result = await db.execute(select(CameraConfig))
    camera_rows = cameras_result.scalars().all()
    camera_by_lower_name = {c.name.lower(): c for c in camera_rows}
    used_lower_names = set(camera_by_lower_name.keys())

    instances_result = await db.execute(select(PipelineInstance))
    instance_rows = instances_result.scalars().all()
    instance_by_camera_id = {
        instance.camera_config_id: instance
        for instance in instance_rows
        if instance.camera_config_id is not None
    }

    transaction = await db.begin()
    try:
        for index, raw_camera in enumerate(payload.cameras, start=1):
            normalized = _normalize_batch_camera_row(raw_camera)
            if normalized is None:
                skipped_count += 1
                processed_count += 1
                report_rows.append({
                    "index": index,
                    "name": f"Row {index}",
                    "action": "skip",
                    "reason": "Missing required fields",
                    "attempts": 1,
                })
                if strict_mode:
                    strict_aborted = True
                    break
                continue

            name = normalized["name"]
            lower_name = name.lower()

            if lower_name in used_lower_names:
                if conflict_strategy == "skip":
                    skipped_count += 1
                    processed_count += 1
                    report_rows.append({
                        "index": index,
                        "name": name,
                        "action": "skip",
                        "reason": "Duplicate name conflict",
                        "attempts": 1,
                    })
                    if strict_mode:
                        strict_aborted = True
                        break
                    continue

                if conflict_strategy == "rename":
                    renamed_name = _generate_unique_camera_name(name, used_lower_names)
                    report_rows.append({
                        "index": index,
                        "name": f"{name} -> {renamed_name}",
                        "action": "rename",
                        "reason": "Auto-renamed due to conflict",
                        "attempts": 1,
                    })
                    name = renamed_name
                    lower_name = name.lower()
                    renamed_count += 1
                elif conflict_strategy == "merge":
                    target_camera = camera_by_lower_name.get(lower_name)
                    if target_camera is None:
                        skipped_count += 1
                        processed_count += 1
                        report_rows.append({
                            "index": index,
                            "name": name,
                            "action": "skip",
                            "reason": "Merge target not found",
                            "attempts": 1,
                        })
                        if strict_mode:
                            strict_aborted = True
                            break
                        continue

                    target_camera.name = name
                    target_camera.source_type = normalized["source_type"]
                    target_camera.source_url = normalized["source_url"]
                    target_camera.group_name = normalized["group_name"]
                    target_camera.enabled_models = normalized["enabled_models"]
                    target_camera.model_configs = normalized["model_configs"]

                    target_instance = instance_by_camera_id.get(target_camera.id)
                    if target_instance is not None:
                        target_instance.name = name
                        target_instance.enabled_models = normalized["enabled_models"]
                        target_instance.model_configs = normalized["model_configs"]

                    await db.flush()

                    merged_count += 1
                    processed_count += 1
                    report_rows.append({
                        "index": index,
                        "name": name,
                        "action": "merge",
                        "reason": "Updated existing camera and instance",
                        "attempts": 1,
                    })
                    continue

            new_camera = CameraConfig(
                name=name,
                source_type=normalized["source_type"],
                source_url=normalized["source_url"],
                group_name=normalized["group_name"],
                enabled_models=normalized["enabled_models"],
                model_configs=normalized["model_configs"],
            )
            db.add(new_camera)
            await db.flush()

            new_instance = PipelineInstance(
                name=name,
                camera_config_id=new_camera.id,
                enabled_models=normalized["enabled_models"],
                model_configs=normalized["model_configs"],
                status="idle",
            )
            db.add(new_instance)
            await db.flush()

            camera_by_lower_name[lower_name] = new_camera
            used_lower_names.add(lower_name)
            instance_by_camera_id[new_camera.id] = new_instance

            created_count += 1
            processed_count += 1
            report_rows.append({
                "index": index,
                "name": name,
                "action": "create",
                "reason": "Created new camera and instance",
                "attempts": 1,
            })

        if strict_aborted:
            remaining = len(payload.cameras) - processed_count
            if remaining > 0:
                skipped_count += remaining
                report_rows.append({
                    "index": processed_count + 1,
                    "name": "-",
                    "action": "cancel",
                    "reason": f"Strict mode aborted remaining {remaining} rows",
                    "attempts": 0,
                })
            await transaction.rollback()
        else:
            await transaction.commit()

    except Exception:
        if transaction.is_active:
            await transaction.rollback()
        raise

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "conflict_strategy": conflict_strategy,
        "mode": mode,
        "summary": {
            "total": len(payload.cameras),
            "processed": processed_count,
            "created": created_count,
            "renamed": renamed_count,
            "merged": merged_count,
            "skipped": skipped_count,
            "cancelled": strict_aborted,
            "committed": not strict_aborted,
            "rolled_back": strict_aborted,
        },
        "rows": report_rows,
    }


@router.post("/", response_model=PipelineInstanceResponse, status_code=status.HTTP_201_CREATED)
async def create_pipeline_instance(
    instance_data: PipelineInstanceCreate,
    db: AsyncSession = Depends(get_db),
):
    """
    Create a new pipeline instance.

    This creates a database record and sends a command to the ML Manager
    to instantiate the pipeline.
    """
    activity_logger = ActivityLogger(db)

    try:
        # Verify camera config exists
        result = await db.execute(
            select(CameraConfig).where(CameraConfig.id == instance_data.camera_config_id)
        )
        camera_config = result.scalar_one_or_none()
        if not camera_config:
            await activity_logger.log_error(
                "create_pipeline_instance",
                f"Camera config {instance_data.camera_config_id} not found",
                extra_data={"camera_config_id": instance_data.camera_config_id}
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Camera config {instance_data.camera_config_id} not found"
            )

        # Create database record
        db_instance = PipelineInstance(
            name=instance_data.name,
            camera_config_id=instance_data.camera_config_id,
            enabled_models=instance_data.enabled_models,
            model_configs=instance_data.model_configs,
            status="idle",
        )
        db.add(db_instance)
        await db.commit()
        await db.refresh(db_instance)

        # Send command to ML Manager via Redis
        redis = await get_redis_client()
        command = {
            "action": "create_instance",
            "instance_id": db_instance.id,
            "name": db_instance.name,
            "camera_source": camera_config.source_url,
            "enabled_models": db_instance.enabled_models,
            "model_configs": db_instance.model_configs,
            "camera_config": {
                "fps": camera_config.fps,
                "width": camera_config.width,
                "height": camera_config.height,
            },
        }
        await redis.publish("pipeline:control", json.dumps(command))

        # Log successful creation
        await activity_logger.log_instance_created(
            db_instance.id,
            db_instance.name,
            camera_config.source_url,
            db_instance.enabled_models
        )

        return db_instance

    except HTTPException:
        raise
    except Exception as e:
        await activity_logger.log_error(
            "create_pipeline_instance",
            f"Unexpected error creating instance: {str(e)}",
            extra_data={"instance_name": instance_data.name, "camera_config_id": instance_data.camera_config_id}
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create pipeline instance"
        )


@router.get("/", response_model=List[PipelineInstanceResponse])
async def list_pipeline_instances(
    status_filter: str = None,
    include_orphans: bool = False,
    db: AsyncSession = Depends(get_db),
):
    """List all pipeline instances, optionally filtered by status.

    By default, instances whose camera_config has been deleted (orphans)
    are hidden — they can't run without a camera and just confuse the UI.
    Pass include_orphans=true to see them anyway.
    """
    query = select(PipelineInstance)
    if not include_orphans:
        query = query.where(PipelineInstance.camera_config_id.isnot(None))
    if status_filter:
        query = query.where(PipelineInstance.status == status_filter)

    result = await db.execute(query.order_by(PipelineInstance.created_at.desc()))
    instances = result.scalars().all()
    return instances


@router.get("/paged")
async def list_pipeline_instances_paged(
    status_filter: str = None,
    group_name: str = None,
    search_query: str = None,
    sort_by: str = "created_at",
    sort_order: str = "desc",
    limit: int = 100,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
):
    """List pipeline instances with pagination for large-scale camera fleets."""
    safe_limit = max(1, min(limit, 500))
    safe_offset = max(0, offset)

    base_query = select(PipelineInstance).outerjoin(
        CameraConfig,
        PipelineInstance.camera_config_id == CameraConfig.id,
    )
    count_query = select(func.count()).select_from(PipelineInstance).outerjoin(
        CameraConfig,
        PipelineInstance.camera_config_id == CameraConfig.id,
    )

    if status_filter:
        base_query = base_query.where(PipelineInstance.status == status_filter)
        count_query = count_query.where(PipelineInstance.status == status_filter)

    if group_name:
        base_query = base_query.where(CameraConfig.group_name == group_name)
        count_query = count_query.where(CameraConfig.group_name == group_name)

    normalized_search = (search_query or "").strip()
    if normalized_search:
        like_pattern = f"%{normalized_search}%"
        search_filter = or_(
            PipelineInstance.name.ilike(like_pattern),
            CameraConfig.name.ilike(like_pattern),
            CameraConfig.group_name.ilike(like_pattern),
        )
        base_query = base_query.where(search_filter)
        count_query = count_query.where(search_filter)

    normalized_sort_by = (sort_by or "created_at").strip().lower()
    normalized_sort_order = (sort_order or "desc").strip().lower()

    sortable_columns = {
        "created_at": PipelineInstance.created_at,
        "name": PipelineInstance.name,
        "status": PipelineInstance.status,
        "camera_name": CameraConfig.name,
        "group_name": CameraConfig.group_name,
    }
    sort_column = sortable_columns.get(normalized_sort_by, PipelineInstance.created_at)

    if normalized_sort_order == "asc":
        ordered_query = base_query.order_by(sort_column.asc(), PipelineInstance.id.asc())
    else:
        ordered_query = base_query.order_by(sort_column.desc(), PipelineInstance.id.desc())

    total_result = await db.execute(count_query)
    total = total_result.scalar_one() or 0

    page_result = await db.execute(
        ordered_query
        .offset(safe_offset)
        .limit(safe_limit)
    )
    items = page_result.scalars().all()

    return {
        "items": items,
        "total": total,
        "limit": safe_limit,
        "offset": safe_offset,
    }


@router.get("/{instance_id}", response_model=PipelineInstanceResponse)
async def get_pipeline_instance(
    instance_id: int,
    db: AsyncSession = Depends(get_db),
):
    """Get a specific pipeline instance by ID."""
    result = await db.execute(
        select(PipelineInstance).where(PipelineInstance.id == instance_id)
    )
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Pipeline instance {instance_id} not found"
        )
    return instance


@router.patch("/{instance_id}", response_model=PipelineInstanceResponse)
async def update_pipeline_instance(
    instance_id: int,
    update_data: PipelineInstanceUpdate,
    db: AsyncSession = Depends(get_db),
):
    """Update pipeline instance metadata (name only - use specific endpoints for models/config)."""
    result = await db.execute(
        select(PipelineInstance).where(PipelineInstance.id == instance_id)
    )
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Pipeline instance {instance_id} not found"
        )

    # Iterate over all set fields rather than hard-coding `name`, so the
    # schema and route stay in sync (previously enabled_models/model_configs
    # were silently dropped here).
    updates = update_data.model_dump(exclude_unset=True)
    for key, value in updates.items():
        setattr(instance, key, value)

    await db.commit()
    await db.refresh(instance)
    return instance


@router.post("/{instance_id}/control", status_code=status.HTTP_202_ACCEPTED)
async def control_pipeline_instance(
    instance_id: int,
    control: PipelineInstanceControl,
    db: AsyncSession = Depends(get_db),
):
    """
    Control a pipeline instance (start, stop, pause, resume).

    Returns HTTP 202 Accepted as the command is sent asynchronously to ML Manager.
    """
    activity_logger = ActivityLogger(db)

    try:
        # Verify instance exists
        result = await db.execute(
            select(PipelineInstance).where(PipelineInstance.id == instance_id)
        )
        instance = result.scalar_one_or_none()
        if not instance:
            await activity_logger.log_error(
                "control_pipeline_instance",
                f"Pipeline instance {instance_id} not found for control action {control.action}",
                extra_data={"instance_id": instance_id, "action": control.action}
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Pipeline instance {instance_id} not found"
            )

        redis = await get_redis_client()

        # For start action, ensure instance exists in ML Manager first
        if control.action == "start":
            # Get camera config
            camera_result = await db.execute(
                select(CameraConfig).where(CameraConfig.id == instance.camera_config_id)
            )
            camera_config = camera_result.scalar_one_or_none()
            if not camera_config:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Camera config {instance.camera_config_id} not found"
                )

            # --- SESSION CREATION ---
            # Create a new session for this run
            new_session = DBSession(
                name=f"Run: {instance.name} ({datetime.now().strftime('%Y-%m-%d %H:%M')})",
                camera_source=camera_config.source_url,
                status="running",
                config=instance.model_configs or {}
            )
            db.add(new_session)
            await db.flush() # Get session ID
            
            # Link instance to session
            instance.session_id = new_session.id
            # ------------------------

            # Send create_instance command first (idempotent - ML Manager will handle if already exists)
            create_command = {
                "action": "create_instance",
                "instance_id": instance_id,
                "name": instance.name,
                "camera_source": camera_config.source_url,
                "enabled_models": instance.enabled_models,
                "model_configs": instance.model_configs,
                "camera_config": {
                    "fps": camera_config.fps,
                    "width": camera_config.width,
                    "height": camera_config.height,
                },
                "session_id": instance.session_id,
            }
            await redis.publish("pipeline:control", json.dumps(create_command))

        # Send control command to ML Manager
        command = {
            "action": control.action,
            "instance_id": instance_id,
        }
        await redis.publish("pipeline:control", json.dumps(command))

        # Update status in database (optimistic)
        status_map = {
            "start": "running",
            "stop": "stopped",
            "pause": "paused",
            "resume": "running",
        }
        old_status = instance.status
        if control.action in status_map:
            instance.status = status_map[control.action]
            await db.commit()

        # Log the control action
        if control.action == "start":
            await activity_logger.log_instance_started(instance_id, instance.name)
        elif control.action == "stop":
            await activity_logger.log_instance_stopped(instance_id, instance.name)
        elif control.action == "pause":
            await activity_logger.log_info(
                "instance_paused",
                f"Pipeline instance '{instance.name}' paused",
                pipeline_instance_id=instance_id,
                extra_data={"action": "pause", "old_status": old_status}
            )
        elif control.action == "resume":
            await activity_logger.log_info(
                "instance_resumed",
                f"Pipeline instance '{instance.name}' resumed",
                pipeline_instance_id=instance_id,
                extra_data={"action": "resume", "old_status": old_status}
            )

        return {
           "message": f"Command '{control.action}' sent to instance {instance_id}",
            "instance_id": instance_id,
            "action": control.action,
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        try:
            await activity_logger.log_error(
                "control_pipeline_instance",
                f"Unexpected error controlling instance {instance_id}: {str(e)}",
                extra_data={"instance_id": instance_id, "action": control.action}
            )
        except Exception:
            # Avoid masking the original control error if logging also fails.
            pass
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to control pipeline instance"
        )


@router.patch("/{instance_id}/models", response_model=PipelineInstanceResponse)
async def update_instance_models(
    instance_id: int,
    models_update: PipelineInstanceModelsUpdate,
    db: AsyncSession = Depends(get_db),
):
    """
    Update which models are enabled for this instance.

    Note: This requires restarting the instance if it's currently running.
    """
    activity_logger = ActivityLogger(db)

    try:
        result = await db.execute(
            select(PipelineInstance).where(PipelineInstance.id == instance_id)
        )
        instance = result.scalar_one_or_none()
        if not instance:
            await activity_logger.log_error(
                "update_instance_models",
                f"Pipeline instance {instance_id} not found for model update",
                extra_data={"instance_id": instance_id, "new_models": models_update.enabled_models}
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Pipeline instance {instance_id} not found"
            )

        # Store old models for logging
        old_models = instance.enabled_models

        # Update database
        instance.enabled_models = models_update.enabled_models
        await db.commit()
        await db.refresh(instance)

        # Send command to ML Manager
        redis = await get_redis_client()
        command = {
            "action": "update_models",
            "instance_id": instance_id,
            "enabled_models": models_update.enabled_models,
        }
        await redis.publish("pipeline:control", json.dumps(command))

        # Log the model update
        await activity_logger.log_info(
            "models_updated",
            f"Pipeline instance '{instance.name}' models updated from {old_models} to {models_update.enabled_models}",
            pipeline_instance_id=instance_id,
            extra_data={"old_models": old_models, "new_models": models_update.enabled_models}
        )

        return instance

    except HTTPException:
        raise
    except Exception as e:
        await activity_logger.log_error(
            "update_instance_models",
            f"Unexpected error updating models for instance {instance_id}: {str(e)}",
            extra_data={"instance_id": instance_id, "new_models": models_update.enabled_models}
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update instance models"
        )


@router.patch("/{instance_id}/config", response_model=PipelineInstanceResponse)
async def update_instance_config(
    instance_id: int,
    config_update: PipelineInstanceConfigUpdate,
    db: AsyncSession = Depends(get_db),
):
    """
    Update model configurations (e.g., confidence thresholds).

    This can be done while the instance is running.
    """
    activity_logger = ActivityLogger(db)

    try:
        result = await db.execute(
            select(PipelineInstance).where(PipelineInstance.id == instance_id)
        )
        instance = result.scalar_one_or_none()
        if not instance:
            await activity_logger.log_error(
                "update_instance_config",
                f"Pipeline instance {instance_id} not found for config update",
                extra_data={"instance_id": instance_id, "new_config": config_update.model_configs}
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Pipeline instance {instance_id} not found"
            )

        # Store old config for logging
        old_config = instance.model_configs or {}

        # Merge configs (deep merge for nested dictionaries)
        current_configs = instance.model_configs or {}

        # Deep merge: for each model in the update, merge its config with existing
        for model_name, new_config in config_update.model_configs.items():
            if model_name in current_configs:
                # Merge existing model config with new config
                current_configs[model_name].update(new_config)
            else:
                # Add new model config
                current_configs[model_name] = new_config

        # Explicitly assign to trigger SQLAlchemy dirty tracking for JSON fields
        instance.model_configs = current_configs

        # Mark the field as modified to ensure SQLAlchemy updates it
        from sqlalchemy.orm import attributes
        attributes.flag_modified(instance, "model_configs")

        await db.commit()
        await db.refresh(instance)

        # Send command to ML Manager for hot-reload
        redis = await get_redis_client()
        command = {
            "action": "update_config",
            "instance_id": instance_id,
            "model_configs": config_update.model_configs,
        }
        await redis.publish("pipeline:control", json.dumps(command))

        # Log the config update
        config_changes = []
        for model_name, new_config in config_update.model_configs.items():
            old_model_config = old_config.get(model_name, {})
            for key, value in new_config.items():
                old_value = old_model_config.get(key, "not set")
                config_changes.append(f"{model_name}.{key}: {old_value} → {value}")

        await activity_logger.log_info(
            "config_updated",
            f"Pipeline instance '{instance.name}' configuration updated: {', '.join(config_changes)}",
            pipeline_instance_id=instance_id,
            extra_data={"old_config": old_config, "new_config": config_update.model_configs}
        )

        return instance

    except HTTPException:
        raise
    except Exception as e:
        await activity_logger.log_error(
            "update_instance_config",
            f"Unexpected error updating config for instance {instance_id}: {str(e)}",
            extra_data={"instance_id": instance_id, "new_config": config_update.model_configs}
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update instance configuration"
        )


@router.delete("/{instance_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_pipeline_instance(
    instance_id: int,
    db: AsyncSession = Depends(get_db),
):
    """
    Delete a pipeline instance.

    This stops the instance (if running) and removes it from the database.
    """
    activity_logger = ActivityLogger(db)

    try:
        result = await db.execute(
            select(PipelineInstance).where(PipelineInstance.id == instance_id)
        )
        instance = result.scalar_one_or_none()
        if not instance:
            await activity_logger.log_error(
                "delete_pipeline_instance",
                f"Pipeline instance {instance_id} not found for deletion",
                extra_data={"instance_id": instance_id}
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Pipeline instance {instance_id} not found"
            )

        # Store instance info for logging
        instance_name = instance.name
        instance_status = instance.status

        # Send stop command to ML Manager
        redis = await get_redis_client()
        command = {
            "action": "delete",
            "instance_id": instance_id,
        }
        await redis.publish("pipeline:control", json.dumps(command))

        # Delete from database (cascade will handle related records)
        await db.delete(instance)
        await db.commit()

        # Log the deletion
        await activity_logger.log_info(
            "instance_deleted",
            f"Pipeline instance '{instance_name}' deleted",
            extra_data={
                "instance_id": instance_id,
                "instance_name": instance_name,
                "previous_status": instance_status,
                "action": "delete"
            }
        )

        return None

    except HTTPException:
        raise
    except Exception as e:
        await activity_logger.log_error(
            "delete_pipeline_instance",
            f"Unexpected error deleting instance {instance_id}: {str(e)}",
            extra_data={"instance_id": instance_id}
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete pipeline instance"
        )


@router.get("/{instance_id}/status")
async def get_instance_status(instance_id: int):
    """
    Get real-time status from Redis (not database).

    This returns the live status from the ML Manager.
    """
    redis = await get_redis_client()
    status_key = f"pipeline:{instance_id}:status"

    status_data = await redis.hgetall(status_key)

    if not status_data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No live status found for instance {instance_id}"
        )

    return status_data
