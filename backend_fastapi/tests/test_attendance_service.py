from datetime import UTC, datetime, timedelta

from app.models.attendance_event import AttendanceEvent
from app.models.student import Student
from app.services.attendance_service import AttendanceService


def test_duplicate_prevention_within_cooldown(db_session) -> None:
    student = Student(full_name="A", class_name="10", section="A", is_active=True)
    db_session.add(student)
    db_session.commit()
    db_session.refresh(student)

    now = datetime.now(UTC)
    event = AttendanceEvent(
        event_uuid="event-1",
        student_id=student.id,
        device_id="ipad-kiosk-1",
        timestamp=now,
        method="auto",
        confidence=0.9,
        similarity=0.85,
        synced=True,
        review_status="not_required",
    )
    db_session.add(event)
    db_session.commit()

    service = AttendanceService(db_session)
    assert service.has_recent_duplicate_student(student.id, within_seconds=300, now=now + timedelta(seconds=10))
    assert not service.has_recent_duplicate_student(student.id, within_seconds=5, now=now + timedelta(seconds=10))
