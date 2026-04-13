from sqlalchemy import Boolean, Float, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models.base import TimestampMixin, UUIDPrimaryKeyMixin


class DeviceSettings(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "device_settings"

    device_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    auto_mark_threshold: Mapped[float] = mapped_column(Float, default=0.72, nullable=False)
    review_threshold: Mapped[float] = mapped_column(Float, default=0.62, nullable=False)
    consecutive_frames_required: Mapped[int] = mapped_column(Integer, default=3, nullable=False)
    min_stable_tracking_seconds: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)
    student_cooldown_seconds: Mapped[int] = mapped_column(Integer, default=300, nullable=False)
    track_cooldown_seconds: Mapped[int] = mapped_column(Integer, default=10, nullable=False)
    min_face_size_ratio: Mapped[float] = mapped_column(Float, default=0.10, nullable=False)
    min_blur_score: Mapped[float] = mapped_column(Float, default=100.0, nullable=False)
    min_brightness: Mapped[float] = mapped_column(Float, default=35.0, nullable=False)
    max_abs_yaw: Mapped[float] = mapped_column(Float, default=20.0, nullable=False)
    max_abs_pitch: Mapped[float] = mapped_column(Float, default=20.0, nullable=False)
    debug_mode: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
