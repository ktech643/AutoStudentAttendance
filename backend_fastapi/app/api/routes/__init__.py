from fastapi import APIRouter

from app.api.routes.analytics import router as analytics_router
from app.api.routes.attendance import router as attendance_router
from app.api.routes.auth import router as auth_router
from app.api.routes.review_queue import router as review_router
from app.api.routes.settings import router as settings_router
from app.api.routes.students import router as students_router

api_router = APIRouter()
api_router.include_router(auth_router)
api_router.include_router(students_router)
api_router.include_router(attendance_router)
api_router.include_router(review_router)
api_router.include_router(settings_router)
api_router.include_router(analytics_router)
