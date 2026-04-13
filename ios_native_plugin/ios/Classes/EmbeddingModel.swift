import Accelerate
import CoreGraphics
import Foundation
import Vision

// MARK: - Protocol

/// Face embedding from a Vision face observation (bounding box + landmarks already computed).
/// Accepting VNFaceObservation directly avoids running a second Vision request on a cropped image.
protocol FaceEmbeddingModel {
  func embedding(from observation: VNFaceObservation) throws -> [Float]
}

enum FaceEmbeddingModelError: Error {
  case noFaceDetected
  case landmarksUnavailable
}

// MARK: - Landmark-based embedding (iOS 11+, stable across all iOS versions)

/// 256-element L2-normalised float vector built from face landmark geometry.
///
/// Steps:
///  1. Collect all landmark points (VNFaceLandmarks2D.allPoints — up to 76 pts).
///  2. Centre by centroid; scale-normalise by inter-ocular distance.
///  3. Flatten [x, y] pairs → 152 floats.
///  4. Add 120 pairwise distances between 16 evenly-spaced key points.
///  5. Pad/trim to 256 elements; L2-normalise.
final class VisionLandmarkEmbeddingModel: FaceEmbeddingModel {

  func embedding(from observation: VNFaceObservation) throws -> [Float] {
    guard let lm = observation.landmarks else {
      throw FaceEmbeddingModelError.landmarksUnavailable
    }
    var pts = collectPoints(lm)
    guard pts.count >= 10 else { throw FaceEmbeddingModelError.landmarksUnavailable }
    pts = centerAndScale(pts, landmarks: lm)
    return normalizeL2(buildVector(pts))
  }

  // MARK: Private helpers

  private func collectPoints(_ lm: VNFaceLandmarks2D) -> [SIMD2<Float>] {
    // allPoints is the canonical superset; fall back to merging regions if absent.
    if let all = lm.allPoints, !all.normalizedPoints.isEmpty {
      return all.normalizedPoints.map { SIMD2(Float($0.x), Float($0.y)) }
    }
    let regions: [VNFaceLandmarkRegion2D?] = [
      lm.faceContour, lm.leftEye, lm.rightEye,
      lm.leftEyebrow, lm.rightEyebrow,
      lm.nose, lm.noseCrest,
      lm.outerLips, lm.innerLips, lm.medianLine,
    ]
    return regions.compactMap { $0 }.flatMap { r in
      r.normalizedPoints.map { SIMD2(Float($0.x), Float($0.y)) }
    }
  }

  private func centerAndScale(_ pts: [SIMD2<Float>], landmarks lm: VNFaceLandmarks2D) -> [SIMD2<Float>] {
    let cx = pts.map(\.x).reduce(0, +) / Float(pts.count)
    let cy = pts.map(\.y).reduce(0, +) / Float(pts.count)
    let centred = pts.map { SIMD2($0.x - cx, $0.y - cy) }

    var iod: Float = 0.12
    if let le = lm.leftEye, let re = lm.rightEye,
       !le.normalizedPoints.isEmpty, !re.normalizedPoints.isEmpty {
      func centroid(_ r: VNFaceLandmarkRegion2D) -> SIMD2<Float> {
        let pts = r.normalizedPoints
        let sx = pts.reduce(0) { $0 + Float($1.x) } / Float(pts.count)
        let sy = pts.reduce(0) { $0 + Float($1.y) } / Float(pts.count)
        return SIMD2(sx, sy)
      }
      let d = centroid(le) - centroid(re)
      iod = max(sqrt(d.x * d.x + d.y * d.y), 0.01)
    }
    return centred.map { SIMD2($0.x / iod, $0.y / iod) }
  }

  private func buildVector(_ pts: [SIMD2<Float>]) -> [Float] {
    var vec: [Float] = []
    vec.reserveCapacity(256)
    // Up to 76 points × 2 = 152 coordinate floats
    for pt in pts.prefix(76) { vec.append(pt.x); vec.append(pt.y) }
    // Pairwise distances between 16 evenly-sampled key points (up to 120 values)
    let step = max(1, pts.count / 16)
    var keys: [Int] = stride(from: 0, to: pts.count, by: step).prefix(16).map { $0 }
    for a in 0..<keys.count {
      for b in (a + 1)..<keys.count {
        let d = pts[keys[a]] - pts[keys[b]]
        vec.append(sqrt(d.x * d.x + d.y * d.y))
      }
    }
    if vec.count < 256 { vec += [Float](repeating: 0, count: 256 - vec.count) }
    return Array(vec.prefix(256))
  }

  private func normalizeL2(_ v: [Float]) -> [Float] {
    var sq: Float = 0
    vDSP_svesq(v, 1, &sq, vDSP_Length(v.count))
    var norm = sqrt(sq)
    guard norm > 1e-6 else { return v }
    var out = v
    vDSP_vsdiv(out, 1, &norm, &out, 1, vDSP_Length(out.count))
    return out
  }
}

// MARK: - Mock (dev / simulator only)

final class MockFaceEmbeddingModel: FaceEmbeddingModel {
  func embedding(from observation: VNFaceObservation) throws -> [Float] {
    let b = observation.boundingBox
    let w = Int(b.width * 9973) + 1
    let h = Int(b.height * 9973) + 1
    var out = [Float](repeating: 0, count: 128)
    for i in 0..<128 {
      let seed = Float((w * (i + 1) + h * (i + 7)) % 997)
      out[i] = (seed / 997.0) * 2.0 - 1.0
    }
    let norm = sqrt(out.reduce(0) { $0 + $1 * $1 })
    return norm > 1e-6 ? out.map { $0 / norm } : out
  }
}

// MARK: - Factory

enum FaceEmbeddingModelFactory {
  static func make() -> FaceEmbeddingModel { VisionLandmarkEmbeddingModel() }
}
