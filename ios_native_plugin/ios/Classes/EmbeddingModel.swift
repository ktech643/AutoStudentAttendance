import Accelerate
import CoreGraphics
import Foundation
import Vision

protocol FaceEmbeddingModel {
  func embedding(from faceImage: CGImage) throws -> [Float]
}

enum FaceEmbeddingModelError: Error {
  case invalidInput
  case noFaceDetected
  case landmarksUnavailable
}

// MARK: - Landmark-based face embedding (iOS 11+, stable across all iOS versions)

/// Extracts a 256-element normalised float embedding from face landmark geometry.
///
/// Pipeline:
///   1. `VNDetectFaceLandmarksRequest` → all 2-D landmark points in face-normalised coords.
///   2. Centre the point cloud (subtract centroid).
///   3. Scale-normalise by the inter-ocular distance (IPD).
///   4. Concatenate [x, y] pairs → 152-dim landmark vector (76 points × 2).
///   5. Augment with 52 pairwise distances between key landmark groups.
///   6. Pad / truncate to exactly 256 floats and L2-normalise.
///
/// Accuracy notes:
///   - Robust to lighting, colour, and moderate pose variation because it uses
///     facial geometry, not pixels.
///   - FAR/FRR performance is lower than a trained neural-net model; suitable
///     for controlled kiosk settings where enrollment quality is managed.
final class VisionLandmarkEmbeddingModel: FaceEmbeddingModel {

  func embedding(from faceImage: CGImage) throws -> [Float] {
    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cgImage: faceImage, options: [:])
    try handler.perform([request])

    guard let face = request.results?.first as? VNFaceObservation else {
      throw FaceEmbeddingModelError.noFaceDetected
    }
    guard let landmarks = face.landmarks else {
      throw FaceEmbeddingModelError.landmarksUnavailable
    }

    var pts = collectPoints(landmarks)
    guard pts.count >= 10 else { throw FaceEmbeddingModelError.landmarksUnavailable }

    pts = centerAndScale(pts, landmarks: landmarks)
    let vec = buildVector(pts)
    return normalizeL2(vec)
  }

  // MARK: - Helpers

  private func collectPoints(_ lm: VNFaceLandmarks2D) -> [SIMD2<Float>] {
    let regions: [VNFaceLandmarkRegion2D?] = [
      lm.allPoints,
      lm.faceContour,
      lm.leftEye,   lm.rightEye,
      lm.leftEyebrow, lm.rightEyebrow,
      lm.nose, lm.noseCrest,
      lm.outerLips, lm.innerLips,
      lm.medianLine,
    ]
    var out: [SIMD2<Float>] = []
    for region in regions.compactMap({ $0 }) {
      for p in region.normalizedPoints {
        out.append(SIMD2(Float(p.x), Float(p.y)))
      }
    }
    // Deduplicate (allPoints overlaps with specific regions)
    if let all = lm.allPoints {
      var deduped: [SIMD2<Float>] = []
      for p in all.normalizedPoints {
        deduped.append(SIMD2(Float(p.x), Float(p.y)))
      }
      return deduped  // use allPoints as the canonical set for consistency
    }
    return out
  }

  /// Centre the point cloud by centroid and normalise scale by inter-ocular distance.
  private func centerAndScale(_ pts: [SIMD2<Float>], landmarks: VNFaceLandmarks2D) -> [SIMD2<Float>] {
    let cx = pts.map(\.x).reduce(0, +) / Float(pts.count)
    let cy = pts.map(\.y).reduce(0, +) / Float(pts.count)
    var centred = pts.map { SIMD2($0.x - cx, $0.y - cy) }

    // Compute inter-ocular distance for scale normalisation
    var iod: Float = 0.1
    if let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
       !leftEye.normalizedPoints.isEmpty, !rightEye.normalizedPoints.isEmpty {
      let le = leftEye.normalizedPoints
      let re = rightEye.normalizedPoints
      let lc = le.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / CGFloat(le.count), y: $0.y + $1.y / CGFloat(le.count)) }
      let rc = re.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / CGFloat(re.count), y: $0.y + $1.y / CGFloat(re.count)) }
      let dx = Float(lc.x - rc.x)
      let dy = Float(lc.y - rc.y)
      iod = max(sqrt(dx * dx + dy * dy), 0.01)
    }

    return centred.map { SIMD2($0.x / iod, $0.y / iod) }
  }

  /// Build a fixed-length descriptor from landmark coordinates + key pairwise distances.
  private func buildVector(_ pts: [SIMD2<Float>]) -> [Float] {
    var vec: [Float] = []
    vec.reserveCapacity(256)

    // Part 1: Flattened [x, y] coordinates (up to 76 points = 152 floats)
    for pt in pts.prefix(76) {
      vec.append(pt.x)
      vec.append(pt.y)
    }

    // Part 2: Pairwise distances between evenly-spaced landmark pairs (up to 104 values)
    let stride = max(1, pts.count / 16)
    var indices: [Int] = []
    var i = 0
    while i < pts.count && indices.count < 16 { indices.append(i); i += stride }

    for a in 0..<indices.count {
      for b in (a + 1)..<indices.count {
        let d = distance(pts[indices[a]], pts[indices[b]])
        vec.append(d)
      }
    }

    // Pad or truncate to exactly 256
    if vec.count < 256 { vec += [Float](repeating: 0, count: 256 - vec.count) }
    return Array(vec.prefix(256))
  }

  private func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    let d = a - b
    return sqrt(d.x * d.x + d.y * d.y)
  }

  private func normalizeL2(_ v: [Float]) -> [Float] {
    var sum: Float = 0
    vDSP_svesq(v, 1, &sum, vDSP_Length(v.count))
    let norm = sqrt(sum)
    guard norm > 1e-6 else { return v }
    var result = v
    var n = norm
    vDSP_vsdiv(result, 1, &n, &result, 1, vDSP_Length(result.count))
    return result
  }
}

// MARK: - Mock fallback (dev / testing only)

final class MockFaceEmbeddingModel: FaceEmbeddingModel {
  func embedding(from faceImage: CGImage) throws -> [Float] {
    let width = max(faceImage.width, 1)
    let height = max(faceImage.height, 1)
    var out = [Float](repeating: 0, count: 128)
    for i in 0..<128 {
      let seed = Float((width * (i + 1) + height * (i + 7)) % 997)
      out[i] = (seed / 997.0) * 2.0 - 1.0
    }
    return normalizeL2(out)
  }

  private func normalizeL2(_ v: [Float]) -> [Float] {
    let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
    guard norm > 1e-6 else { return v }
    return v.map { $0 / norm }
  }
}

// MARK: - Factory

enum FaceEmbeddingModelFactory {
  static func make() -> FaceEmbeddingModel {
    return VisionLandmarkEmbeddingModel()
  }
}
