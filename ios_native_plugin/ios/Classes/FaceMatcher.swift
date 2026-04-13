import Foundation

struct MatchCandidate {
  let studentId: String
  let studentName: String
  let similarity: Double
  let confidence: Double
}

final class FaceMatcher {
  private let embeddingStore: EmbeddingStore

  init(embeddingStore: EmbeddingStore) {
    self.embeddingStore = embeddingStore
  }

  func reloadEmbeddings() {
    embeddingStore.reload()
  }

  func bestMatch(for query: [Float]) -> MatchCandidate? {
    let candidates = scoreCandidates(for: query, topK: 1)
    return candidates.first
  }

  func topCandidates(for query: [Float], topK: Int = 3) -> [MatchCandidate] {
    return scoreCandidates(for: query, topK: topK)
  }

  private func scoreCandidates(for query: [Float], topK: Int) -> [MatchCandidate] {
    let normalized = normalize(query)
    let enrolled = embeddingStore.allEmbeddings()
    let scored = enrolled.map { item in
      let score = cosineSimilarity(normalized, normalize(item.vector))
      return MatchCandidate(
        studentId: item.studentId,
        studentName: item.studentName,
        similarity: score,
        confidence: score
      )
    }.sorted { $0.similarity > $1.similarity }
    return Array(scored.prefix(topK))
  }

  private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
    guard a.count == b.count else { return 0.0 }
    var dot: Float = 0
    for i in 0..<a.count {
      dot += a[i] * b[i]
    }
    return Double(dot)
  }

  private func normalize(_ vector: [Float]) -> [Float] {
    let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
    guard norm > 0 else { return vector }
    return vector.map { $0 / norm }
  }
}
