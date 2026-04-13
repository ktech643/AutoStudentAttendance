from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.models.attendance_event import AttendanceEvent
from app.models.unknown_face_review import UnknownFaceReview
from app.schemas.attendance import AttendanceEventCreate, RecognitionCandidate


class AttendanceService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create_event(self, payload: AttendanceEventCreate) -> tuple[AttendanceEvent, bool, bool]:
        """
        Returns (event, is_duplicate, review_created).
        """
        event, is_duplicate, review_created = self.create_event_non_committing(payload)
        if is_duplicate:
            return event, True, review_created
        self.db.commit()
        self.db.refresh(event)
        return event, False, review_created

    def bulk_sync(self, events: list[AttendanceEventCreate]) -> tuple[int, int, int]:
        accepted = 0
        duplicates = 0
        reviews = 0
        # Keep a single transaction for bulk throughput.
        try:
            for event_payload in events:
                _, is_duplicate, review_created = self.create_event_non_committing(event_payload)
                if is_duplicate:
                    duplicates += 1
                    continue
                accepted += 1
                if review_created:
                    reviews += 1
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise
        return accepted, duplicates, reviews

    def create_event_non_committing(self, payload: AttendanceEventCreate) -> tuple[AttendanceEvent, bool, bool]:
        existing = self.db.scalar(select(AttendanceEvent).where(AttendanceEvent.event_uuid == payload.event_uuid))
        if existing:
            return existing, True, False

        event = AttendanceEvent(
            event_uuid=payload.event_uuid,
            student_id=payload.student_id,
            device_id=payload.device_id,
            timestamp=payload.timestamp,
            method=payload.method,
            confidence=payload.confidence,
            similarity=payload.similarity,
            synced=True,
            review_status=payload.review_status,
            image_snapshot_path=payload.image_snapshot_path,
        )
        self.db.add(event)
        self.db.flush()

        review_created = False
        if payload.review_status == "pending":
            review_item = UnknownFaceReview(
                event_id=event.id,
                snapshot_path=payload.image_snapshot_path,
                top_candidates=[candidate.model_dump() for candidate in payload.top_candidates],
                reason=payload.reason or "borderline_similarity",
                status="pending",
            )
            self.db.add(review_item)
            review_created = True
        return event, False, review_created

    def recent(self, limit: int = 50) -> list[AttendanceEvent]:
        query = select(AttendanceEvent).order_by(AttendanceEvent.timestamp.desc()).limit(limit)
        return list(self.db.scalars(query).all())

    def today_summary(self) -> tuple[int, int]:
        now = datetime.now(UTC)
        start = datetime(now.year, now.month, now.day, tzinfo=UTC)
        end = start + timedelta(days=1)

        events = self.db.scalars(
            select(AttendanceEvent).where(and_(AttendanceEvent.timestamp >= start, AttendanceEvent.timestamp < end))
        ).all()
        total_marked = len([event for event in events if event.student_id is not None])
        total_review_pending = len([event for event in events if event.review_status == "pending"])
        return total_marked, total_review_pending

    def has_recent_duplicate_student(self, student_id: str, within_seconds: int, now: datetime) -> bool:
        window_start = now - timedelta(seconds=within_seconds)
        event = self.db.scalar(
            select(AttendanceEvent)
            .where(
                and_(
                    AttendanceEvent.student_id == student_id,
                    AttendanceEvent.timestamp >= window_start,
                    AttendanceEvent.timestamp <= now,
                )
            )
            .order_by(AttendanceEvent.timestamp.desc())
            .limit(1)
        )
        return event is not None


def candidate_dicts_to_models(raw_candidates: list[dict]) -> list[RecognitionCandidate]:
    return [RecognitionCandidate(**candidate) for candidate in raw_candidates]
