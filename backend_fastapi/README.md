# Backend FastAPI Module

Production-minded backend for face attendance.

## Stack
- FastAPI
- SQLAlchemy 2.x
- Alembic
- PostgreSQL
- JWT auth for admin endpoints

## Run locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
alembic upgrade head
uvicorn app.main:app --reload
```

Open API docs:
- Swagger: `http://127.0.0.1:8000/docs`
- ReDoc: `http://127.0.0.1:8000/redoc`

## Main endpoints
- `POST /auth/login`
- `GET/POST/PUT/DELETE /students`
- `POST /students/{id}/enroll`
- `POST /students/{id}/embeddings`
- `GET /students/{id}/embeddings`
- `DELETE /embeddings/{id}`
- `POST /attendance/events`
- `POST /attendance/events/bulk-sync`
- `GET /attendance/logs`
- `GET /attendance/today`
- `GET /attendance/recent`
- `GET /review-queue`
- `POST /review-queue/{id}/approve`
- `POST /review-queue/{id}/reject`
- `GET /settings`
- `PUT /settings`

## Privacy defaults
- Embeddings are in `face_embeddings`; student profile endpoints do not return vectors.
- Review actions are written to `audit_logs`.

## Testing

```bash
pytest -q
```
