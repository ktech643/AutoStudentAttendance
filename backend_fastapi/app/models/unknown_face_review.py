from sqlalchemy import ForeignKey, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin, UUIDPrimaryKeyMixin


class UnknownFaceReview(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "unknown_face_reviews"

    event_id: Mapped[str] = mapped_column(ForeignKey("attendance_events.id", ondelete="CASCADE"), nullable=False, unique=True)
    snapshot_path: Mapped[str | None] = mapped_column(String(256), nullable=True)
    top_candidates: Mapped[list[dict]] = mapped_column(JSON, default=list, nullable=False)
    reason: Mapped[str] = mapped_column(String(128), nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="pending", nullable=False, index=True)

    attendance_event = relationship("AttendanceEvent", back_populates="review_item")
