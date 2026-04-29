"""
Alert rule management routes.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models import AlertRule, PipelineInstance
from app.schemas import AlertRuleCreate, AlertRuleUpdate, AlertRuleResponse


router = APIRouter(prefix="/api/alerts", tags=["Alert Rules"])


@router.get("/", response_model=list[AlertRuleResponse])
async def list_alert_rules(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(AlertRule).order_by(AlertRule.created_at.desc()))
    return result.scalars().all()


@router.post("/", response_model=AlertRuleResponse, status_code=status.HTTP_201_CREATED)
async def create_alert_rule(
    payload: AlertRuleCreate,
    db: AsyncSession = Depends(get_db),
):
    if payload.pipeline_instance_id is not None:
        instance_result = await db.execute(
            select(PipelineInstance.id).where(PipelineInstance.id == payload.pipeline_instance_id)
        )
        if instance_result.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Pipeline instance {payload.pipeline_instance_id} not found",
            )

    db_rule = AlertRule(
        name=payload.name,
        description=payload.description,
        pipeline_instance_id=payload.pipeline_instance_id,
        model_name=payload.model_name,
        trigger_condition=payload.trigger_condition.model_dump(),
        actions=payload.actions.model_dump(),
        cooldown_seconds=payload.cooldown_seconds,
    )
    db.add(db_rule)
    await db.commit()
    await db.refresh(db_rule)
    return db_rule


@router.get("/{rule_id}", response_model=AlertRuleResponse)
async def get_alert_rule(rule_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(AlertRule).where(AlertRule.id == rule_id))
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert rule not found")
    return rule


@router.patch("/{rule_id}", response_model=AlertRuleResponse)
async def update_alert_rule(
    rule_id: int,
    payload: AlertRuleUpdate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(AlertRule).where(AlertRule.id == rule_id))
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert rule not found")

    update_data = payload.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        if key == "trigger_condition" and value is not None:
            setattr(rule, key, value.model_dump())
        elif key == "actions" and value is not None:
            setattr(rule, key, value.model_dump())
        else:
            setattr(rule, key, value)

    await db.commit()
    await db.refresh(rule)
    return rule


@router.delete("/{rule_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_alert_rule(rule_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(AlertRule).where(AlertRule.id == rule_id))
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert rule not found")

    await db.delete(rule)
    await db.commit()
