from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.core.database import get_db
from app.models.device_settings import DeviceSettings
from app.schemas.settings import DeviceSettingsResponse, DeviceSettingsUpdate

router = APIRouter(tags=["settings"])


def _create_default_settings(db: Session, device_id: str) -> DeviceSettings:
    settings = DeviceSettings(device_id=device_id)
    db.add(settings)
    db.commit()
    db.refresh(settings)
    return settings


@router.get("/settings", response_model=DeviceSettingsResponse)
def get_settings(device_id: str, db: Session = Depends(get_db), _: object = Depends(require_admin)) -> DeviceSettings:
    settings = db.scalar(select(DeviceSettings).where(DeviceSettings.device_id == device_id))
    return settings or _create_default_settings(db, device_id)


@router.put("/settings", response_model=DeviceSettingsResponse)
def update_settings(
    payload: DeviceSettingsUpdate,
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
) -> DeviceSettings:
    settings = db.scalar(select(DeviceSettings).where(DeviceSettings.device_id == payload.device_id))
    if not settings:
        settings = DeviceSettings(**payload.model_dump())
        db.add(settings)
        db.commit()
        db.refresh(settings)
        return settings

    for key, value in payload.model_dump().items():
        setattr(settings, key, value)
    db.commit()
    db.refresh(settings)
    return settings
