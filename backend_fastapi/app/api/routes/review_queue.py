from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.core.database import get_db
from app.schemas.common import MessageResponse
from app.schemas.review import ReviewApproveRequest, ReviewQueueItemResponse, ReviewRejectRequest
from app.services.review_service import ReviewService

router = APIRouter(prefix="/review-queue", tags=["review"])


@router.get("", response_model=list[ReviewQueueItemResponse])
def list_review_queue(db: Session = Depends(get_db), _: object = Depends(require_admin)) -> list:
    return ReviewService(db).list_pending()


@router.post("/{review_id}/approve", response_model=MessageResponse)
def approve_review(
    review_id: str,
    payload: ReviewApproveRequest,
    db: Session = Depends(get_db),
    current_user = Depends(require_admin),
) -> MessageResponse:
    ReviewService(db).approve(review_id, payload.student_id, current_user.id)
    return MessageResponse(message="Review item approved")


@router.post("/{review_id}/reject", response_model=MessageResponse)
def reject_review(
    review_id: str,
    payload: ReviewRejectRequest,
    db: Session = Depends(get_db),
    current_user = Depends(require_admin),
) -> MessageResponse:
    ReviewService(db).reject(review_id, current_user.id, payload.reason)
    return MessageResponse(message="Review item rejected")
