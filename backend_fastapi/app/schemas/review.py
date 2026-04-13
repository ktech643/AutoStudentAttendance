from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.schemas.attendance import RecognitionCandidate


class ReviewQueueItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    event_id: str
    snapshot_path: str | None
    top_candidates: list[RecognitionCandidate]
    reason: str
    status: str
    created_at: datetime


class ReviewApproveRequest(BaseModel):
    student_id: str


class ReviewRejectRequest(BaseModel):
    reason: str
