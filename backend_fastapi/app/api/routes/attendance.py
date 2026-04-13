from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.core.database import get_db
from app.models.attendance_event import AttendanceEvent
from app.models.device_settings import DeviceSettings
from app.models.student import Student
from app.schemas.attendance import (
    AttendanceEventCreate,
    AttendanceEventResponse,
    AttendanceSummaryResponse,
    BulkSyncRequest,
    BulkSyncResponse,
)
from app.services.attendance_service import AttendanceService

router = APIRouter(prefix="/attendance", tags=["attendance"])


def _resolve_student_cooldown(db: Session, device_id: str) -> int:
    settings = db.scalar(select(DeviceSettings).where(DeviceSettings.device_id == device_id))
    return settings.student_cooldown_seconds if settings else 300


@router.post("/events", response_model=AttendanceEventResponse, status_code=status.HTTP_201_CREATED)
def create_event(
    payload: AttendanceEventCreate,
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
) -> AttendanceEvent:
    service = AttendanceService(db)
    if payload.student_id:
        cooldown = _resolve_student_cooldown(db, payload.device_id)
        if service.has_recent_duplicate_student(payload.student_id, cooldown, now=payload.timestamp):
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Duplicate attendance within cooldown")

    event, _, _ = service.create_event(payload)
    return event


@router.post("/events/bulk-sync", response_model=BulkSyncResponse)
def bulk_sync(
    payload: BulkSyncRequest,
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
) -> BulkSyncResponse:
    service = AttendanceService(db)
    accepted, duplicates, reviews = service.bulk_sync(payload.events)
    return BulkSyncResponse(accepted=accepted, duplicates=duplicates, review_items_created=reviews)


@router.get("/logs", response_model=list[AttendanceEventResponse])
def attendance_logs(
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
    date: str | None = Query(default=None),
    class_name: str | None = Query(default=None),
    section: str | None = Query(default=None),
    review_status: str | None = Query(default=None),
) -> list[AttendanceEvent]:
    query = select(AttendanceEvent)

    if date:
        try:
            day = datetime.fromisoformat(date)
        except ValueError as exc:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Invalid date format") from exc
        start = datetime(day.year, day.month, day.day, tzinfo=UTC)
        end = start + timedelta(days=1)
        query = query.where(and_(AttendanceEvent.timestamp >= start, AttendanceEvent.timestamp < end))
    if review_status:
        query = query.where(AttendanceEvent.review_status == review_status)
    if class_name or section:
        query = query.join(Student, AttendanceEvent.student_id == Student.id)
        if class_name:
            query = query.where(Student.class_name == class_name)
        if section:
            query = query.where(Student.section == section)

    query = query.order_by(AttendanceEvent.timestamp.desc())
    return list(db.scalars(query).all())


@router.get("/today", response_model=AttendanceSummaryResponse)
def attendance_today(
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
) -> AttendanceSummaryResponse:
    service = AttendanceService(db)
    total_marked, total_review_pending = service.today_summary()
    return AttendanceSummaryResponse(
        date=datetime.now(UTC).date().isoformat(),
        total_marked=total_marked,
        total_review_pending=total_review_pending,
    )


@router.get("/recent", response_model=list[AttendanceEventResponse])
def attendance_recent(
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
    limit: int = Query(default=20, ge=1, le=100),
) -> list[AttendanceEvent]:
    service = AttendanceService(db)
    return service.recent(limit=limit)
