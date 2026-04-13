import AVFoundation
import Foundation
import Vision

/// Runs face detection + landmark extraction in a single Vision pass per frame (8 fps),
/// then computes embeddings and matches against enrolled templates.
///
/// Performance notes:
///  - One VNDetectFaceLandmarksRequest replaces the previous two-request approach
///    (VNDetectFaceRectanglesRequest + a second landmark request on the cropped image).
///  - The AVCaptureSession is injected (owned by FaceAttendancePlugin) so the same
///    session can also feed the camera preview PlatformView without conflict.
final class FaceRecognitionPipeline: NSObject {
  private let embeddingModel: FaceEmbeddingModel
  private let matcher: FaceMatcher
  private let qualityGate = QualityGate()
  private let onEvent: (RecognitionEventPayload) -> Void
  private var thresholds = RecognitionThresholds.defaultThresholds

  // Injected shared session (also used by CameraPreviewPlatformView)
  private let captureSession: AVCaptureSession
  private let videoOutput = AVCaptureVideoDataOutput()
  private let videoQueue = DispatchQueue(label: "face.attendance.capture.queue", qos: .userInitiated)
  private let processingQueue = DispatchQueue(label: "face.attendance.processing.queue", qos: .userInitiated)

  private var frameCount = 0
  private var recognitionAttempts = 0
  private var successfulMatches = 0
  private var rejectedByQuality = 0
  private var duplicatePrevented = 0
  private var lastProcessedAt = Date.distantPast
  private var debugMode = false
  private var trackLastDecisionAt: [Int: Date] = [:]
  private var studentLastMarkAt: [String: Date] = [:]
  private var trackedFaces: [Int: CGRect] = [:]
  private var nextTrackId = 1

  init(
    embeddingModel: FaceEmbeddingModel,
    matcher: FaceMatcher,
    captureSession: AVCaptureSession,
    onEvent: @escaping (RecognitionEventPayload) -> Void
  ) {
    self.embeddingModel = embeddingModel
    self.matcher = matcher
    self.captureSession = captureSession
    self.onEvent = onEvent
    super.init()
  }

  // MARK: - Control

  func setThresholds(_ v: RecognitionThresholds) { thresholds = v }
  func setDebugMode(_ v: Bool) { debugMode = v }
  func reloadEmbeddings() { matcher.reloadEmbeddings() }
  func loadEnrolledEmbeddings(_ list: [[String: Any]]) { matcher.loadEmbeddings(list) }

  func start() {
    configureOutputIfNeeded()
    if !captureSession.isRunning { captureSession.startRunning() }
  }

  func stop() {
    if captureSession.isRunning { captureSession.stopRunning() }
  }

  // MARK: - Session configuration

  private func configureOutputIfNeeded() {
    // Only add input/output once; the preview layer is already attached to the session.
    guard captureSession.outputs.isEmpty else { return }

    captureSession.beginConfiguration()
    captureSession.sessionPreset = .hd1280x720

    if captureSession.inputs.isEmpty {
      if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
         let input = try? AVCaptureDeviceInput(device: device),
         captureSession.canAddInput(input) {
        captureSession.addInput(input)
      }
    }

    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
    ]
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

    if captureSession.canAddOutput(videoOutput) {
      captureSession.addOutput(videoOutput)
    }
    if let conn = videoOutput.connection(with: .video) {
      if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
      if conn.isVideoMirroringSupported { conn.isVideoMirrored = true }
    }

    captureSession.commitConfiguration()
  }

  // MARK: - Frame processing

  private func processFrame(_ sampleBuffer: CMSampleBuffer) {
    let now = Date()
    guard now.timeIntervalSince(lastProcessedAt) >= (1.0 / 8.0) else { return }
    lastProcessedAt = now
    frameCount += 1

    // Single Vision pass: landmarks include the bounding box, so no second request needed.
    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored, options: [:])
    do { try handler.perform([request]) } catch { return }

    guard let faces = request.results as? [VNFaceObservation], !faces.isEmpty else {
      trackedFaces.removeAll()
      return
    }

    let detectionMs = Date().timeIntervalSince(now) * 1000
    let tracked = assignTrackIds(faces)

    for (trackId, observation) in tracked {
      let quality = qualityGate.evaluate(observation: observation, sampleBuffer: sampleBuffer, thresholds: thresholds)

      guard quality.accepted else {
        rejectedByQuality += 1
        emitEvent(trackId: trackId, matched: nil, similarity: 0, confidence: 0,
                  quality: quality.score, box: observation.boundingBox,
                  accepted: false, rejectReason: quality.reason, topCandidates: [],
                  detectionMs: detectionMs, embeddingMs: 0, matchingMs: 0)
        continue
      }

      let t1 = Date()
      guard let embedding = try? embeddingModel.embedding(from: observation) else { continue }
      let embeddingMs = Date().timeIntervalSince(t1) * 1000

      let t2 = Date()
      recognitionAttempts += 1
      let candidates = matcher.topCandidates(for: embedding, topK: 3)
      let best = candidates.first
      let matchingMs = Date().timeIntervalSince(t2) * 1000

      if let m = best {
        if shouldSuppress(trackId: trackId, studentId: m.studentId, now: now) {
          duplicatePrevented += 1
          continue
        }
        if m.similarity >= thresholds.autoMarkThreshold { successfulMatches += 1 }
      }

      emitEvent(trackId: trackId, matched: best,
                similarity: best?.similarity ?? 0, confidence: best?.confidence ?? 0,
                quality: quality.score, box: observation.boundingBox,
                accepted: true, rejectReason: nil, topCandidates: candidates,
                detectionMs: detectionMs, embeddingMs: embeddingMs, matchingMs: matchingMs)

      if debugMode {
        NSLog("pipeline frame=%d attempts=%d matches=%d rejected=%d detect=%.1fms embed=%.1fms match=%.1fms",
              frameCount, recognitionAttempts, successfulMatches, rejectedByQuality,
              detectionMs, embeddingMs, matchingMs)
      }
    }
  }

  // MARK: - Track ID assignment (nearest-box matching)

  private func assignTrackIds(_ faces: [VNFaceObservation]) -> [(Int, VNFaceObservation)] {
    var result: [(Int, VNFaceObservation)] = []
    var used = Set<Int>()
    for face in faces {
      let cx = face.boundingBox.midX
      let cy = face.boundingBox.midY
      var chosen: Int? = nil
      var bestDist: CGFloat = 999
      for (tid, prev) in trackedFaces {
        guard !used.contains(tid) else { continue }
        let dx = prev.midX - cx
        let dy = prev.midY - cy
        let d = sqrt(dx * dx + dy * dy)
        if d < bestDist { bestDist = d; chosen = tid }
      }
      let tid: Int
      if let c = chosen, bestDist < 0.20 { tid = c } else { tid = nextTrackId; nextTrackId += 1 }
      used.insert(tid)
      trackedFaces[tid] = face.boundingBox
      result.append((tid, face))
    }
    trackedFaces = trackedFaces.filter { used.contains($0.key) }
    return result
  }

  private func shouldSuppress(trackId: Int, studentId: String, now: Date) -> Bool {
    if let t = trackLastDecisionAt[trackId], now.timeIntervalSince(t) < Double(thresholds.trackCooldownSeconds) { return true }
    if let t = studentLastMarkAt[studentId], now.timeIntervalSince(t) < Double(thresholds.studentCooldownSeconds) { return true }
    trackLastDecisionAt[trackId] = now
    studentLastMarkAt[studentId] = now
    return false
  }

  // MARK: - Event emission (convert Vision bottom-left → Flutter top-left)

  private func emitEvent(
    trackId: Int, matched: MatchCandidate?,
    similarity: Double, confidence: Double, quality: Double,
    box: CGRect, accepted: Bool, rejectReason: String?,
    topCandidates: [MatchCandidate],
    detectionMs: Double, embeddingMs: Double, matchingMs: Double
  ) {
    let displayY = 1.0 - box.origin.y - box.height
    let payload = RecognitionEventPayload(
      trackId: trackId,
      matchedStudentId: matched?.studentId,
      matchedStudentName: matched?.studentName,
      matchedStudentRollNumber: matched?.rollNumber,
      confidence: confidence, similarity: similarity,
      faceBox: FaceBox(x: box.origin.x, y: displayY, w: box.width, h: box.height),
      qualityScore: quality,
      timestamp: ISO8601DateFormatter().string(from: Date()),
      imageAcceptedForRecognition: accepted,
      reasonIfRejected: rejectReason,
      topCandidates: topCandidates.map {
        RecognitionCandidatePayload(studentId: $0.studentId, studentName: $0.studentName,
                                    rollNumber: $0.rollNumber, similarity: $0.similarity, confidence: $0.confidence)
      }
    )
    DispatchQueue.main.async { [onEvent] in onEvent(payload) }
  }
}

extension FaceRecognitionPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    processingQueue.async { [weak self] in self?.processFrame(sampleBuffer) }
  }
}
