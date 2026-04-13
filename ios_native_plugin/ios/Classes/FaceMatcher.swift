import Foundation

struct MatchCandidate {
  let studentId: String
  let studentName: String
  let rollNumber: String
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

  func loadEmbeddings(_ list: [[String: Any]]) {
    embeddingStore.loadFromList(list)
  }

  func bestMatch(for query: [Float]) -> MatchCandidate? {
    return topCandidates(for: query, topK: 1).first
  }

  func topCandidates(for query: [Float], topK: Int = 3) -> [MatchCandidate] {
    let normalized = normalizeL2(query)
    let enrolled = embeddingStore.allEmbeddings()
    guard !enrolled.isEmpty else { return [] }
    let scored = enrolled.map { item -> MatchCandidate in
      let sim = cosineSimilarity(normalized, normalizeL2(item.vector))
      return MatchCandidate(
        studentId: item.studentId,
        studentName: item.studentName,
        rollNumber: item.rollNumber,
        similarity: sim,
        confidence: sim
      )
    }.sorted { $0.similarity > $1.similarity }
    return Array(scored.prefix(topK))
  }

  private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
    let len = min(a.count, b.count)
    guard len > 0 else { return 0.0 }
    var dot: Float = 0
    for i in 0..<len { dot += a[i] * b[i] }
    return Double(dot)
  }

  private func normalizeL2(_ v: [Float]) -> [Float] {
    let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
    guard norm > 1e-6 else { return v }
    return v.map { $0 / norm }
  }
}
