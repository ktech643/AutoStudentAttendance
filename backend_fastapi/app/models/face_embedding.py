from sqlalchemy import Float, ForeignKey, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin, UUIDPrimaryKeyMixin


class FaceEmbedding(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "face_embeddings"

    student_id: Mapped[str] = mapped_column(ForeignKey("students.id", ondelete="CASCADE"), nullable=False, index=True)
    vector: Mapped[list[float]] = mapped_column(JSON, nullable=False)
    source_type: Mapped[str] = mapped_column(String(32), default="enrollment_capture", nullable=False)
    quality_score: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)

    student = relationship("Student", back_populates="embeddings")
