from datetime import UTC, datetime


def _auth_headers(client) -> dict[str, str]:
    response = client.post(
        "/auth/login",
        json={"email": "admin@school.com", "password": "changeMe123"},
    )
    assert response.status_code == 200
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_student_create_validation(client) -> None:
    headers = _auth_headers(client)
    response = client.post(
        "/students",
        headers=headers,
        json={
            "full_name": "",
            "class_name": "10",
            "section": "A",
            "is_active": True,
        },
    )
    assert response.status_code == 422


def test_attendance_idempotent_event_uuid(client) -> None:
    headers = _auth_headers(client)
    student = client.post(
        "/students",
        headers=headers,
        json={
            "full_name": "Student One",
            "class_name": "10",
            "section": "A",
            "is_active": True,
        },
    ).json()

    payload = {
        "event_uuid": "event-uuid-123456",
        "student_id": student["id"],
        "device_id": "ipad-kiosk-1",
        "timestamp": datetime.now(UTC).isoformat(),
        "method": "auto",
        "confidence": 0.90,
        "similarity": 0.88,
        "review_status": "not_required",
    }
    first = client.post("/attendance/events", headers=headers, json=payload)
    assert first.status_code == 201
    second = client.post("/attendance/events", headers=headers, json=payload)
    assert second.status_code in (201, 409)
