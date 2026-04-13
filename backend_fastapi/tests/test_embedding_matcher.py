import pytest

from app.services.embedding_matcher import cosine_similarity, find_best_match, normalize_embedding


def test_cosine_similarity_identical_vectors_close_to_one() -> None:
    vector = [0.2, 0.4, 0.6, 0.8]
    similarity = cosine_similarity(vector, vector)
    assert similarity == pytest.approx(1.0, rel=1e-6)


def test_normalize_embedding_keeps_vector_length() -> None:
    normalized = normalize_embedding([2.0, 0.0, 0.0, 0.0])
    assert len(normalized) == 4
    assert normalized[0] == pytest.approx(1.0, rel=1e-6)


def test_find_best_match_returns_highest_similarity() -> None:
    query = [1.0, 0.0, 0.0]
    enrolled = {
        "student-a": [[1.0, 0.0, 0.0]],
        "student-b": [[0.0, 1.0, 0.0]],
    }
    best = find_best_match(query, enrolled)
    assert best is not None
    assert best.student_id == "student-a"
