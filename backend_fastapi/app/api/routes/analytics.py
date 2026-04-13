from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.core.database import get_db
from app.models.attendance_event import AttendanceEvent
from app.models.unknown_face_review import UnknownFaceReview

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/counters")
def counters(db: Session = Depends(get_db), _: object = Depends(require_admin)) -> dict[str, int]:
    total_events = db.scalar(select(func.count()).select_from(AttendanceEvent)) or 0
    total_reviews = db.scalar(select(func.count()).select_from(UnknownFaceReview)) or 0
    pending_reviews = (
        db.scalar(select(func.count()).select_from(UnknownFaceReview).where(UnknownFaceReview.status == "pending")) or 0
    )
    return {
        "total_events": int(total_events),
        "total_review_items": int(total_reviews),
        "pending_review_items": int(pending_reviews),
    }
