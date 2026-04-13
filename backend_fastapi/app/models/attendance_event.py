from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin, UUIDPrimaryKeyMixin


class AttendanceEvent(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "attendance_events"
    __table_args__ = (
        UniqueConstraint("event_uuid", name="uq_attendance_event_uuid"),
    )

    event_uuid: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    student_id: Mapped[str | None] = mapped_column(ForeignKey("students.id", ondelete="SET NULL"), nullable=True, index=True)
    device_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    method: Mapped[str] = mapped_column(String(32), default="auto", nullable=False)
    confidence: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    similarity: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    synced: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    review_status: Mapped[str] = mapped_column(String(32), default="not_required", nullable=False, index=True)
    image_snapshot_path: Mapped[str | None] = mapped_column(String(256), nullable=True)

    student = relationship("Student", back_populates="attendance_events")
    review_item = relationship("UnknownFaceReview", back_populates="attendance_event", uselist=False)
