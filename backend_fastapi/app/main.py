import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from app.api.routes import api_router
from app.core.config import get_settings
from app.core.database import Base, SessionLocal, engine
from app.core.logging import configure_logging
from app.core.security import get_password_hash
from app.models.user import User

settings = get_settings()
configure_logging()
logger = logging.getLogger("attendance-api")

app = FastAPI(
    title="Face Attendance API",
    version="0.1.0",
    description="Backend API for student face attendance with review queue and offline-safe idempotent event ingestion.",
)
# Browser-based Flutter web uses a different origin (port) than the API; allow dev/testing clients.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(api_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.on_event("startup")
def startup() -> None:
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        admin = db.scalar(select(User).where(User.email == settings.default_admin_email))
        if not admin:
            db.add(
                User(
                    email=settings.default_admin_email,
                    hashed_password=get_password_hash(settings.default_admin_password),
                    role="admin",
                    is_active=True,
                )
            )
            db.commit()
            logger.info("Created default admin user %s", settings.default_admin_email)
