from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.core.database import get_db
from app.models.face_embedding import FaceEmbedding
from app.models.student import Student
from app.schemas.embedding import EmbeddingBulkItem, EmbeddingCreate, EmbeddingDebugResponse, EmbeddingResponse
from app.schemas.student import (
    StudentCreate,
    StudentEnrollmentRequest,
    StudentEnrollmentResponse,
    StudentResponse,
    StudentUpdate,
)
from app.services.embedding_matcher import normalize_embedding

router = APIRouter(tags=["students"])


@router.get("/students", response_model=list[StudentResponse])
def list_students(
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
    search: str | None = Query(default=None),
) -> list[Student]:
    query = select(Student).order_by(Student.full_name.asc())
    if search:
        search_term = f"%{search}%"
        query = query.where(
            or_(Student.full_name.ilike(search_term), Student.roll_number.ilike(search_term), Student.external_id.ilike(search_term))
        )
    return list(db.scalars(query).all())


@router.post("/students", response_model=StudentResponse, status_code=status.HTTP_201_CREATED)
def create_student(payload: StudentCreate, db: Session = Depends(get_db), _: object = Depends(require_admin)) -> Student:
    student = Student(**payload.model_dump())
    db.add(student)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Duplicate roll number or external ID") from exc
    db.refresh(student)
    return student


@router.get("/students/{student_id}", response_model=StudentResponse)
def get_student(student_id: str, db: Session = Depends(get_db), _: object = Depends(require_admin)) -> Student:
    student = db.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    return student


@router.put("/students/{student_id}", response_model=StudentResponse)
def update_student(
    student_id: str, payload: StudentUpdate, db: Session = Depends(get_db), _: object = Depends(require_admin)
) -> Student:
    student = db.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(student, key, value)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Duplicate roll number or external ID") from exc
    db.refresh(student)
    return student


@router.delete("/students/{student_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_student(student_id: str, db: Session = Depends(get_db), _: object = Depends(require_admin)) -> None:
    student = db.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    db.delete(student)
    db.commit()


@router.post("/students/{student_id}/enroll", response_model=StudentEnrollmentResponse)
def enroll_student(
    student_id: str,
    payload: StudentEnrollmentRequest,
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
) -> StudentEnrollmentResponse:
    student = db.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    if len(payload.embeddings) != len(payload.quality_scores):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Embeddings and quality scores mismatch")

    for vector, quality in zip(payload.embeddings, payload.quality_scores, strict=True):
        db.add(
            FaceEmbedding(
                student_id=student_id,
                vector=normalize_embedding(vector),
                source_type=payload.source_type,
                quality_score=quality,
            )
        )
    db.commit()

    total = db.scalar(select(func.count()).select_from(FaceEmbedding).where(FaceEmbedding.student_id == student_id))
    status_value = "complete" if total and total >= 5 else "needs_more_images"
    return StudentEnrollmentResponse(student_id=student_id, embedding_count=total or 0, enrollment_status=status_value)


@router.post("/students/{student_id}/embeddings", response_model=EmbeddingResponse, status_code=status.HTTP_201_CREATED)
def add_embedding(
    student_id: str,
    payload: EmbeddingCreate,
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
) -> FaceEmbedding:
    student = db.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")

    embedding = FaceEmbedding(
        student_id=student_id,
        vector=normalize_embedding(payload.vector),
        source_type=payload.source_type,
        quality_score=payload.quality_score,
    )
    db.add(embedding)
    db.commit()
    db.refresh(embedding)
    return embedding


@router.get("/students/{student_id}/embeddings", response_model=list[EmbeddingResponse])
def get_embeddings(student_id: str, db: Session = Depends(get_db), _: object = Depends(require_admin)) -> list[FaceEmbedding]:
    student = db.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    return list(db.scalars(select(FaceEmbedding).where(FaceEmbedding.student_id == student_id)).all())


@router.get("/students/{student_id}/embeddings/debug", response_model=list[EmbeddingDebugResponse])
def get_embeddings_debug(student_id: str, db: Session = Depends(get_db), _: object = Depends(require_admin)) -> list[FaceEmbedding]:
    student = db.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    return list(db.scalars(select(FaceEmbedding).where(FaceEmbedding.student_id == student_id)).all())


@router.get("/embeddings/all", response_model=list[EmbeddingBulkItem])
def list_all_embeddings_for_device(
    db: Session = Depends(get_db),
    _: object = Depends(require_admin),
) -> list[EmbeddingBulkItem]:
    """Return every embedding with student info for device-side face matching.

    Only includes active students. Vectors are normalized (unit length).
    """
    rows = db.execute(
        select(
            FaceEmbedding.id,
            FaceEmbedding.student_id,
            FaceEmbedding.vector,
            FaceEmbedding.quality_score,
            Student.full_name,
            Student.roll_number,
        )
        .join(Student, Student.id == FaceEmbedding.student_id)
        .where(Student.is_active.is_(True))
        .order_by(FaceEmbedding.quality_score.desc())
    ).all()
    return [
        EmbeddingBulkItem(
            embedding_id=r.id,
            student_id=r.student_id,
            student_name=r.full_name,
            roll_number=r.roll_number,
            vector=r.vector,
            quality_score=r.quality_score,
        )
        for r in rows
    ]


@router.delete("/embeddings/{embedding_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_embedding(embedding_id: str, db: Session = Depends(get_db), _: object = Depends(require_admin)) -> None:
    embedding = db.get(FaceEmbedding, embedding_id)
    if not embedding:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Embedding not found")
    db.delete(embedding)
    db.commit()
