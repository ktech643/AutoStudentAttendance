from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class RecognitionCandidate(BaseModel):
    student_id: str
    student_name: str
    similarity: float = Field(ge=0, le=1)
    confidence: float = Field(ge=0, le=1)


class AttendanceEventCreate(BaseModel):
    event_uuid: str = Field(min_length=8, max_length=64)
    student_id: str | None = None
    device_id: str = Field(min_length=1, max_length=64)
    timestamp: datetime
    method: str = Field(default="auto", pattern="^(auto|manual|review-approved)$")
    confidence: float = Field(ge=0, le=1)
    similarity: float = Field(ge=0, le=1)
    review_status: str = Field(default="not_required", pattern="^(not_required|pending|approved|rejected)$")
    image_snapshot_path: str | None = None
    top_candidates: list[RecognitionCandidate] = Field(default_factory=list)
    reason: str | None = None


class AttendanceEventResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    event_uuid: str
    student_id: str | None
    device_id: str
    timestamp: datetime
    method: str
    confidence: float
    similarity: float
    synced: bool
    review_status: str
    image_snapshot_path: str | None
    created_at: datetime


class BulkSyncRequest(BaseModel):
    events: list[AttendanceEventCreate] = Field(min_length=1, max_length=500)


class BulkSyncResponse(BaseModel):
    accepted: int
    duplicates: int
    review_items_created: int


class AttendanceSummaryResponse(BaseModel):
    date: str
    total_marked: int
    total_review_pending: int
