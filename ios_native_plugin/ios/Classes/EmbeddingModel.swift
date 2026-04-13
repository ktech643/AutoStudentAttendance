import CoreGraphics
import Foundation

protocol FaceEmbeddingModel {
  func embedding(from faceImage: CGImage) throws -> [Float]
}

enum FaceEmbeddingModelError: Error {
  case invalidInput
  case modelNotLoaded
}

final class MockFaceEmbeddingModel: FaceEmbeddingModel {
  func embedding(from faceImage: CGImage) throws -> [Float] {
    // Development-only deterministic pseudo embedding for simulator and UI testing.
    // Replace this with real ArcFace/CoreML adapter in production integration.
    let width = max(faceImage.width, 1)
    let height = max(faceImage.height, 1)
    var output: [Float] = []
    output.reserveCapacity(128)
    for index in 0..<128 {
      let seed = Float((width * (index + 1) + height * (index + 7)) % 997)
      output.append((seed / 997.0) * 2.0 - 1.0)
    }
    return normalize(output)
  }

  private func normalize(_ vector: [Float]) -> [Float] {
    let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
    guard norm > 0 else { return vector }
    return vector.map { $0 / norm }
  }
}

/*
 TODO(CoreML):
 1) Add ArcFace-style CoreML model to plugin bundle.
 2) Implement CoreMLFaceEmbeddingModel conforming to FaceEmbeddingModel.
 3) Preprocess face crop (alignment, color normalization, input size).
 4) Run model on background queue and normalize output vector.
 5) Add warmup/inference metrics + failure fallback.
 */
