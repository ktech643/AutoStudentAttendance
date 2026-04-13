from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class DeviceSettingsBase(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)
    auto_mark_threshold: float = Field(ge=0.5, le=0.95, default=0.72)
    review_threshold: float = Field(ge=0.4, le=0.9, default=0.62)
    consecutive_frames_required: int = Field(ge=1, le=10, default=3)
    min_stable_tracking_seconds: float = Field(ge=0.2, le=5.0, default=1.0)
    student_cooldown_seconds: int = Field(ge=30, le=1800, default=300)
    track_cooldown_seconds: int = Field(ge=1, le=120, default=10)
    min_face_size_ratio: float = Field(ge=0.03, le=0.6, default=0.10)
    min_blur_score: float = Field(ge=10.0, le=1000.0, default=100.0)
    min_brightness: float = Field(ge=5.0, le=200.0, default=35.0)
    max_abs_yaw: float = Field(ge=5.0, le=45.0, default=20.0)
    max_abs_pitch: float = Field(ge=5.0, le=45.0, default=20.0)
    debug_mode: bool = False


class DeviceSettingsUpdate(DeviceSettingsBase):
    pass


class DeviceSettingsResponse(DeviceSettingsBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    created_at: datetime
    updated_at: datetime
