"""initial schema

Revision ID: 20260412_0001
Revises:
Create Date: 2026-04-12 00:00:00.000000
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "20260412_0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "students",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("external_id", sa.String(length=64), nullable=True, unique=True),
        sa.Column("roll_number", sa.String(length=64), nullable=True, unique=True),
        sa.Column("full_name", sa.String(length=128), nullable=False),
        sa.Column("class_name", sa.String(length=64), nullable=False),
        sa.Column("section", sa.String(length=32), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_students_full_name", "students", ["full_name"])
    op.create_index("ix_students_class_name", "students", ["class_name"])
    op.create_index("ix_students_section", "students", ["section"])

    op.create_table(
        "users",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("email", sa.String(length=128), nullable=False, unique=True),
        sa.Column("hashed_password", sa.String(length=256), nullable=False),
        sa.Column("role", sa.String(length=32), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    op.create_table(
        "device_settings",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("device_id", sa.String(length=64), nullable=False, unique=True),
        sa.Column("auto_mark_threshold", sa.Float(), nullable=False),
        sa.Column("review_threshold", sa.Float(), nullable=False),
        sa.Column("consecutive_frames_required", sa.Integer(), nullable=False),
        sa.Column("min_stable_tracking_seconds", sa.Float(), nullable=False),
        sa.Column("student_cooldown_seconds", sa.Integer(), nullable=False),
        sa.Column("track_cooldown_seconds", sa.Integer(), nullable=False),
        sa.Column("min_face_size_ratio", sa.Float(), nullable=False),
        sa.Column("min_blur_score", sa.Float(), nullable=False),
        sa.Column("min_brightness", sa.Float(), nullable=False),
        sa.Column("max_abs_yaw", sa.Float(), nullable=False),
        sa.Column("max_abs_pitch", sa.Float(), nullable=False),
        sa.Column("debug_mode", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "face_embeddings",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("student_id", sa.String(length=36), sa.ForeignKey("students.id", ondelete="CASCADE"), nullable=False),
        sa.Column("vector", sa.JSON(), nullable=False),
        sa.Column("source_type", sa.String(length=32), nullable=False),
        sa.Column("quality_score", sa.Float(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_face_embeddings_student_id", "face_embeddings", ["student_id"])

    op.create_table(
        "attendance_events",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("event_uuid", sa.String(length=64), nullable=False),
        sa.Column("student_id", sa.String(length=36), sa.ForeignKey("students.id", ondelete="SET NULL"), nullable=True),
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column("timestamp", sa.DateTime(timezone=True), nullable=False),
        sa.Column("method", sa.String(length=32), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("similarity", sa.Float(), nullable=False),
        sa.Column("synced", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("review_status", sa.String(length=32), nullable=False),
        sa.Column("image_snapshot_path", sa.String(length=256), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("event_uuid", name="uq_attendance_event_uuid"),
    )
    op.create_index("ix_attendance_events_event_uuid", "attendance_events", ["event_uuid"])
    op.create_index("ix_attendance_events_student_id", "attendance_events", ["student_id"])
    op.create_index("ix_attendance_events_device_id", "attendance_events", ["device_id"])
    op.create_index("ix_attendance_events_timestamp", "attendance_events", ["timestamp"])
    op.create_index("ix_attendance_events_review_status", "attendance_events", ["review_status"])

    op.create_table(
        "unknown_face_reviews",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("event_id", sa.String(length=36), sa.ForeignKey("attendance_events.id", ondelete="CASCADE"), nullable=False),
        sa.Column("snapshot_path", sa.String(length=256), nullable=True),
        sa.Column("top_candidates", sa.JSON(), nullable=False),
        sa.Column("reason", sa.String(length=128), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("event_id", name="uq_unknown_face_reviews_event_id"),
    )
    op.create_index("ix_unknown_face_reviews_status", "unknown_face_reviews", ["status"])

    op.create_table(
        "audit_logs",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("actor_user_id", sa.String(length=36), nullable=False),
        sa.Column("action", sa.String(length=64), nullable=False),
        sa.Column("target_type", sa.String(length=64), nullable=False),
        sa.Column("target_id", sa.String(length=64), nullable=False),
        sa.Column("details", sa.String(length=512), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_audit_logs_actor_user_id", "audit_logs", ["actor_user_id"])
    op.create_index("ix_audit_logs_action", "audit_logs", ["action"])


def downgrade() -> None:
    op.drop_index("ix_audit_logs_action", table_name="audit_logs")
    op.drop_index("ix_audit_logs_actor_user_id", table_name="audit_logs")
    op.drop_table("audit_logs")

    op.drop_index("ix_unknown_face_reviews_status", table_name="unknown_face_reviews")
    op.drop_table("unknown_face_reviews")

    op.drop_index("ix_attendance_events_review_status", table_name="attendance_events")
    op.drop_index("ix_attendance_events_timestamp", table_name="attendance_events")
    op.drop_index("ix_attendance_events_device_id", table_name="attendance_events")
    op.drop_index("ix_attendance_events_student_id", table_name="attendance_events")
    op.drop_index("ix_attendance_events_event_uuid", table_name="attendance_events")
    op.drop_table("attendance_events")

    op.drop_index("ix_face_embeddings_student_id", table_name="face_embeddings")
    op.drop_table("face_embeddings")

    op.drop_table("device_settings")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
    op.drop_index("ix_students_section", table_name="students")
    op.drop_index("ix_students_class_name", table_name="students")
    op.drop_index("ix_students_full_name", table_name="students")
    op.drop_table("students")
