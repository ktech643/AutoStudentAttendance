import Foundation

struct EnrolledEmbedding {
  let studentId: String
  let studentName: String
  let rollNumber: String
  let vector: [Float]
}

protocol EmbeddingStore {
  func allEmbeddings() -> [EnrolledEmbedding]
  func reload()
  func loadFromList(_ list: [[String: Any]])
}

final class InMemoryEmbeddingStore: EmbeddingStore {
  private var embeddings: [EnrolledEmbedding] = []
  private let queue = DispatchQueue(label: "face.attendance.embedding.store", attributes: .concurrent)

  init() {}

  func allEmbeddings() -> [EnrolledEmbedding] {
    return queue.sync { embeddings }
  }

  func reload() {
    // Called by Flutter's reloadEmbeddings channel method.
    // The real refresh is via loadFromList after fetching from the server.
  }

  /// Replaces the in-memory store with embeddings received from Flutter (fetched from the backend).
  /// Expected keys per item: studentId (String), studentName (String),
  /// rollNumber (String?), vector ([Double] or [Float]).
  func loadFromList(_ list: [[String: Any]]) {
    var loaded: [EnrolledEmbedding] = []
    for item in list {
      guard
        let studentId = item["studentId"] as? String,
        let studentName = item["studentName"] as? String,
        let vectorAny = item["vector"] as? [Any], !vectorAny.isEmpty
      else { continue }
      let rollNumber = item["rollNumber"] as? String ?? ""
      var floats: [Float] = []
      floats.reserveCapacity(vectorAny.count)
      for v in vectorAny {
        if let d = v as? Double { floats.append(Float(d)) }
        else if let f = v as? Float { floats.append(f) }
      }
      guard !floats.isEmpty else { continue }
      loaded.append(
        EnrolledEmbedding(
          studentId: studentId,
          studentName: studentName,
          rollNumber: rollNumber,
          vector: normalizeL2(floats)
        )
      )
    }
    queue.async(flags: .barrier) { [weak self] in
      self?.embeddings = loaded
    }
  }

  private func normalizeL2(_ v: [Float]) -> [Float] {
    let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
    guard norm > 1e-6 else { return v }
    return v.map { $0 / norm }
  }
}
