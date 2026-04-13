import Foundation

struct RecognitionThresholds {
  let autoMarkThreshold: Double
  let reviewThreshold: Double
  let consecutiveFramesRequired: Int
  let minStableTrackingSeconds: Double
  let studentCooldownSeconds: Int
  let trackCooldownSeconds: Int
  let minFaceSizeRatio: Double
  let minBlurScore: Double
  let minBrightness: Double
  let maxAbsYaw: Double
  let maxAbsPitch: Double
  let debugMode: Bool

  static let defaultThresholds = RecognitionThresholds(
    autoMarkThreshold: 0.72,
    reviewThreshold: 0.62,
    consecutiveFramesRequired: 3,
    minStableTrackingSeconds: 1.0,
    studentCooldownSeconds: 300,
    trackCooldownSeconds: 10,
    minFaceSizeRatio: 0.10,
    minBlurScore: 100.0,
    minBrightness: 35.0,
    maxAbsYaw: 20.0,
    maxAbsPitch: 20.0,
    debugMode: false
  )
}

struct FaceBox {
  let x: Double
  let y: Double
  let w: Double
  let h: Double
}

struct RecognitionCandidatePayload {
  let studentId: String
  let studentName: String
  let similarity: Double
  let confidence: Double

  func toDictionary() -> [String: Any] {
    return [
      "studentId": studentId,
      "studentName": studentName,
      "similarity": similarity,
      "confidence": confidence
    ]
  }
}

struct RecognitionEventPayload {
  let trackId: Int
  let matchedStudentId: String?
  let matchedStudentName: String?
  let confidence: Double
  let similarity: Double
  let faceBox: FaceBox?
  let qualityScore: Double
  let timestamp: String
  let imageAcceptedForRecognition: Bool
  let reasonIfRejected: String?
  let topCandidates: [RecognitionCandidatePayload]

  func toDictionary() -> [String: Any] {
    var payload: [String: Any] = [
      "trackId": trackId,
      "matchedStudentId": matchedStudentId as Any,
      "matchedStudentName": matchedStudentName as Any,
      "confidence": confidence,
      "similarity": similarity,
      "qualityScore": qualityScore,
      "timestamp": timestamp,
      "imageAcceptedForRecognition": imageAcceptedForRecognition,
      "reasonIfRejected": reasonIfRejected as Any,
      "topCandidates": topCandidates.map { $0.toDictionary() }
    ]
    if let faceBox = faceBox {
      payload["faceBox"] = [
        "x": faceBox.x,
        "y": faceBox.y,
        "w": faceBox.w,
        "h": faceBox.h
      ]
    }
    return payload
  }
}
