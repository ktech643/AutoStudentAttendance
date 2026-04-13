from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class EmbeddingCreate(BaseModel):
    vector: list[float] = Field(min_length=64, max_length=1024)
    source_type: str = "manual_upload"
    quality_score: float = Field(ge=0, le=1)


class EmbeddingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    student_id: str
    source_type: str
    quality_score: float
    created_at: datetime


class EmbeddingDebugResponse(EmbeddingResponse):
    vector: list[float]


class EmbeddingBulkItem(BaseModel):
    """One enrolled embedding with its student metadata — used for device-side matching."""

    embedding_id: str
    student_id: str
    student_name: str
    roll_number: str | None
    vector: list[float]
    quality_score: float
