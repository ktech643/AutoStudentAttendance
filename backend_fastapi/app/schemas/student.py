from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class StudentBase(BaseModel):
    external_id: str | None = Field(default=None, max_length=64)
    roll_number: str | None = Field(default=None, max_length=64)
    full_name: str = Field(min_length=1, max_length=128)
    class_name: str = Field(min_length=1, max_length=64)
    section: str = Field(min_length=1, max_length=32)
    is_active: bool = True


class StudentCreate(StudentBase):
    pass


class StudentUpdate(BaseModel):
    external_id: str | None = Field(default=None, max_length=64)
    roll_number: str | None = Field(default=None, max_length=64)
    full_name: str | None = Field(default=None, min_length=1, max_length=128)
    class_name: str | None = Field(default=None, min_length=1, max_length=64)
    section: str | None = Field(default=None, min_length=1, max_length=32)
    is_active: bool | None = None


class StudentResponse(StudentBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    embedding_count: int = 0
    created_at: datetime
    updated_at: datetime


class StudentEnrollmentRequest(BaseModel):
    source_type: str = "enrollment_capture"
    embeddings: list[list[float]] = Field(min_length=1, max_length=10)
    quality_scores: list[float] = Field(min_length=1, max_length=10)


class StudentEnrollmentResponse(BaseModel):
    student_id: str
    embedding_count: int
    enrollment_status: str
