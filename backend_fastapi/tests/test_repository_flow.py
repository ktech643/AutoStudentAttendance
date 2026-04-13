from datetime import UTC, datetime

from app.models.student import Student
from app.schemas.attendance import AttendanceEventCreate
from app.services.attendance_service import AttendanceService


def test_attendance_service_create_and_recent(db_session) -> None:
    student = Student(full_name="Repo Flow", class_name="10", section="A", is_active=True)
    db_session.add(student)
    db_session.commit()
    db_session.refresh(student)

    service = AttendanceService(db_session)
    payload = AttendanceEventCreate(
        event_uuid="repo-flow-event-1",
        student_id=student.id,
        device_id="ipad-1",
        timestamp=datetime.now(UTC),
        method="auto",
        confidence=0.91,
        similarity=0.87,
        review_status="not_required",
    )
    _, duplicate, review_created = service.create_event(payload)
    assert not duplicate
    assert not review_created

    recent = service.recent(limit=10)
    assert len(recent) >= 1
