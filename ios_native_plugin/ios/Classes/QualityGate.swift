import AVFoundation
import Vision

struct QualityGateResult {
  let accepted: Bool
  let score: Double
  let reason: String?
}

final class QualityGate {
  func evaluate(
    observation: VNFaceObservation,
    sampleBuffer: CMSampleBuffer,
    thresholds: RecognitionThresholds
  ) -> QualityGateResult {
    let box = observation.boundingBox
    let area = Double(box.width * box.height)
    let sizeAccepted = area >= thresholds.minFaceSizeRatio
    if !sizeAccepted {
      return QualityGateResult(accepted: false, score: 0.2, reason: "face_too_small")
    }

    let yaw: Double = {
      if #available(iOS 15.0, *) {
        return abs(observation.yaw?.doubleValue ?? 0.0)
      }
      return 0.0
    }()
    let pitch: Double = {
      if #available(iOS 15.0, *) {
        return abs(observation.pitch?.doubleValue ?? 0.0)
      }
      return 0.0
    }()
    if yaw > thresholds.maxAbsYaw || pitch > thresholds.maxAbsPitch {
      return QualityGateResult(accepted: false, score: 0.3, reason: "pose_out_of_range")
    }

    let brightness = estimateBrightness(sampleBuffer: sampleBuffer)
    if brightness < thresholds.minBrightness {
      return QualityGateResult(accepted: false, score: 0.4, reason: "too_dark")
    }

    let blur = estimateBlur(sampleBuffer: sampleBuffer)
    if blur < thresholds.minBlurScore {
      return QualityGateResult(accepted: false, score: 0.5, reason: "too_blurry")
    }

    let score = min(1.0, (area * 1.5 + blur / 300.0 + brightness / 120.0) / 3.0)
    return QualityGateResult(accepted: true, score: score, reason: nil)
  }

  private func estimateBrightness(sampleBuffer: CMSampleBuffer) -> Double {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return 0.0 }
    CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0) else { return 0.0 }
    let width = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
    let height = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
    let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)

    let sampleStep = 8
    var sum: UInt64 = 0
    var count: UInt64 = 0
    for y in stride(from: 0, to: height, by: sampleStep) {
      let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
      for x in stride(from: 0, to: width, by: sampleStep) {
        sum += UInt64(row[x])
        count += 1
      }
    }
    guard count > 0 else { return 0.0 }
    return Double(sum) / Double(count)
  }

  private func estimateBlur(sampleBuffer: CMSampleBuffer) -> Double {
    // Placeholder blur estimate (proxy from luma variance sampling).
    // TODO: Replace with Laplacian variance using Accelerate/vImage for production tuning.
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return 0.0 }
    CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0) else { return 0.0 }
    let width = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
    let height = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
    let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)

    let sampleStep = 8
    var values: [Double] = []
    values.reserveCapacity((width / sampleStep) * (height / sampleStep))
    for y in stride(from: 0, to: height, by: sampleStep) {
      let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
      for x in stride(from: 0, to: width, by: sampleStep) {
        values.append(Double(row[x]))
      }
    }
    guard !values.isEmpty else { return 0.0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { partial, value in
      let diff = value - mean
      return partial + (diff * diff)
    } / Double(values.count)
    return variance / 10.0
  }
}
