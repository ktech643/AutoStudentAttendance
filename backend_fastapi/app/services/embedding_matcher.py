from dataclasses import dataclass
from math import sqrt


@dataclass(frozen=True)
class MatchResult:
    student_id: str
    similarity: float


def normalize_embedding(vector: list[float]) -> list[float]:
    norm = sqrt(sum(value * value for value in vector))
    if norm == 0:
        return vector
    return [value / norm for value in vector]


def cosine_similarity(a: list[float], b: list[float]) -> float:
    if len(a) != len(b):
        raise ValueError("Embedding lengths must match")
    a_norm = normalize_embedding(a)
    b_norm = normalize_embedding(b)
    return float(sum(x * y for x, y in zip(a_norm, b_norm, strict=True)))


def find_best_match(
    query_embedding: list[float],
    student_embeddings: dict[str, list[list[float]]],
) -> MatchResult | None:
    best: MatchResult | None = None
    for student_id, embeddings in student_embeddings.items():
        for embedding in embeddings:
            score = cosine_similarity(query_embedding, embedding)
            if best is None or score > best.similarity:
                best = MatchResult(student_id=student_id, similarity=score)
    return best


def top_k_matches(
    query_embedding: list[float],
    student_embeddings: dict[str, list[list[float]]],
    k: int = 3,
) -> list[MatchResult]:
    scores: list[MatchResult] = []
    for student_id, embeddings in student_embeddings.items():
        best_for_student = max((cosine_similarity(query_embedding, e) for e in embeddings), default=0.0)
        scores.append(MatchResult(student_id=student_id, similarity=best_for_student))
    scores.sort(key=lambda item: item.similarity, reverse=True)
    return scores[:k]
