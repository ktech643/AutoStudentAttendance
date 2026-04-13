def _auth_headers(client) -> dict[str, str]:
    response = client.post(
        "/auth/login",
        json={"email": "admin@school.com", "password": "changeMe123"},
    )
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_review_approve_flow(client) -> None:
    headers = _auth_headers(client)
    student = client.post(
        "/students",
        headers=headers,
        json={
            "full_name": "Review Student",
            "class_name": "10",
            "section": "A",
            "is_active": True,
        },
    ).json()

    event_response = client.post(
        "/attendance/events",
        headers=headers,
        json={
            "event_uuid": "review-event-1",
            "student_id": None,
            "device_id": "ipad-1",
            "timestamp": "2026-04-12T12:00:00Z",
            "method": "auto",
            "confidence": 0.64,
            "similarity": 0.64,
            "review_status": "pending",
            "top_candidates": [
                {
                    "student_id": student["id"],
                    "student_name": student["full_name"],
                    "similarity": 0.64,
                    "confidence": 0.64,
                }
            ],
            "reason": "borderline_similarity",
        },
    )
    assert event_response.status_code == 201

    queue = client.get("/review-queue", headers=headers)
    assert queue.status_code == 200
    items = queue.json()
    assert len(items) >= 1

    review_id = items[0]["id"]
    approve = client.post(
        f"/review-queue/{review_id}/approve",
        headers=headers,
        json={"student_id": student["id"]},
    )
    assert approve.status_code == 200
