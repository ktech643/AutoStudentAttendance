from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.attendance_event import AttendanceEvent
from app.models.audit_log import AuditLog
from app.models.unknown_face_review import UnknownFaceReview


class ReviewService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def list_pending(self) -> list[UnknownFaceReview]:
        return list(self.db.scalars(select(UnknownFaceReview).where(UnknownFaceReview.status == "pending")).all())

    def approve(self, review_id: str, student_id: str, actor_user_id: str) -> UnknownFaceReview:
        review = self.db.get(UnknownFaceReview, review_id)
        if not review:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Review item not found")
        if review.status != "pending":
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Review item already resolved")

        event = self.db.get(AttendanceEvent, review.event_id)
        if not event:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Related attendance event not found")

        event.student_id = student_id
        event.method = "review-approved"
        event.review_status = "approved"
        review.status = "approved"

        self.db.add(
            AuditLog(
                actor_user_id=actor_user_id,
                action="review_approved",
                target_type="unknown_face_review",
                target_id=review_id,
                details=f"Assigned event {event.id} to student {student_id}",
            )
        )
        self.db.commit()
        self.db.refresh(review)
        return review

    def reject(self, review_id: str, actor_user_id: str, reason: str) -> UnknownFaceReview:
        review = self.db.get(UnknownFaceReview, review_id)
        if not review:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Review item not found")
        if review.status != "pending":
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Review item already resolved")

        event = self.db.get(AttendanceEvent, review.event_id)
        if not event:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Related attendance event not found")
        event.review_status = "rejected"
        review.status = "rejected"
        review.reason = reason
        self.db.add(
            AuditLog(
                actor_user_id=actor_user_id,
                action="review_rejected",
                target_type="unknown_face_review",
                target_id=review_id,
                details=reason,
            )
        )
        self.db.commit()
        self.db.refresh(review)
        return review
