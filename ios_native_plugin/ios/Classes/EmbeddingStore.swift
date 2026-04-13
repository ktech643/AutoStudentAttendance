import Foundation

struct EnrolledEmbedding {
  let studentId: String
  let studentName: String
  let vector: [Float]
}

protocol EmbeddingStore {
  func allEmbeddings() -> [EnrolledEmbedding]
  func reload()
}

final class InMemoryEmbeddingStore: EmbeddingStore {
  private var embeddings: [EnrolledEmbedding] = []
  private let queue = DispatchQueue(label: "face.attendance.embedding.store", qos: .userInitiated)

  init() {
    // Example seed records for dev/simulated mode.
    embeddings = [
      EnrolledEmbedding(studentId: "student-11", studentName: "Sim Student 1", vector: Self.randomUnitVector(seed: 11)),
      EnrolledEmbedding(studentId: "student-12", studentName: "Sim Student 2", vector: Self.randomUnitVector(seed: 12)),
      EnrolledEmbedding(studentId: "student-13", studentName: "Sim Student 3", vector: Self.randomUnitVector(seed: 13))
    ]
  }

  func allEmbeddings() -> [EnrolledEmbedding] {
    return queue.sync { embeddings }
  }

  func reload() {
    queue.sync {
      // TODO: Pull latest embeddings from secure local cache or backend sync layer.
      // Keep vectors and student mapping in memory for low-latency matching.
    }
  }

  private static func randomUnitVector(seed: Int) -> [Float] {
    var values: [Float] = []
    values.reserveCapacity(128)
    for i in 0..<128 {
      let raw = Float(((seed + 31) * (i + 7)) % 503) / 503.0
      values.append(raw * 2.0 - 1.0)
    }
    let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
    return norm > 0 ? values.map { $0 / norm } : values
  }
}
