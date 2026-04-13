from app.schemas.settings import DeviceSettingsUpdate


def test_thresholds_validation_defaults() -> None:
    settings = DeviceSettingsUpdate(device_id="ipad-1")
    assert settings.auto_mark_threshold == 0.72
    assert settings.review_threshold == 0.62
