import AVFoundation
import CoreImage
import Foundation
import Vision

final class FaceRecognitionPipeline: NSObject {
  private let embeddingModel: FaceEmbeddingModel
  private let matcher: FaceMatcher
  private let qualityGate = QualityGate()
  private let onEvent: (RecognitionEventPayload) -> Void
  private var thresholds = RecognitionThresholds.defaultThresholds

  private let captureSession = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let videoQueue = DispatchQueue(label: "face.attendance.capture.queue", qos: .userInitiated)
  private let processingQueue = DispatchQueue(label: "face.attendance.processing.queue", qos: .userInitiated)
  private let ciContext = CIContext()

  private var frameCount = 0
  private var recognitionAttempts = 0
  private var successfulMatches = 0
  private var rejectedByQuality = 0
  private var duplicatePrevented = 0
  private var lastProcessedAt = Date.distantPast
  private var debugMode = false
  private var trackLastDecisionAt: [Int: Date] = [:]
  private var studentLastMarkAt: [String: Date] = [:]
  private var trackedObservations: [Int: VNDetectedObjectObservation] = [:]
  private var nextTrackId: Int = 1

  init(
    embeddingModel: FaceEmbeddingModel,
    matcher: FaceMatcher,
    onEvent: @escaping (RecognitionEventPayload) -> Void
  ) {
    self.embeddingModel = embeddingModel
    self.matcher = matcher
    self.onEvent = onEvent
    super.init()
  }

  func setThresholds(_ value: RecognitionThresholds) {
    thresholds = value
  }

  func setDebugMode(_ enabled: Bool) {
    debugMode = enabled
  }

  func reloadEmbeddings() {
    matcher.reloadEmbeddings()
  }

  func start() {
    configureCaptureSessionIfNeeded()
    if !captureSession.isRunning {
      captureSession.startRunning()
    }
  }

  func stop() {
    if captureSession.isRunning {
      captureSession.stopRunning()
    }
  }

  private func configureCaptureSessionIfNeeded() {
    if !captureSession.inputs.isEmpty {
      return
    }

    captureSession.beginConfiguration()
    captureSession.sessionPreset = .high

    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
      captureSession.commitConfiguration()
      return
    }

    do {
      let input = try AVCaptureDeviceInput(device: device)
      if captureSession.canAddInput(input) {
        captureSession.addInput(input)
      }
      videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
      if captureSession.canAddOutput(videoOutput) {
        captureSession.addOutput(videoOutput)
      }
      if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
        connection.videoOrientation = .portrait
      }
    } catch {
      captureSession.commitConfiguration()
      return
    }

    captureSession.commitConfiguration()
  }

  private func processFrame(_ sampleBuffer: CMSampleBuffer) {
    let now = Date()
    let elapsed = now.timeIntervalSince(lastProcessedAt)
    if elapsed < (1.0 / 8.0) {
      return
    }
    lastProcessedAt = now
    frameCount += 1

    let t0 = Date()
    let observations = detectFaces(sampleBuffer: sampleBuffer)
    let detectionMs = Date().timeIntervalSince(t0) * 1000
    guard !observations.isEmpty else {
      return
    }

    for tracked in observations {
      let trackId = tracked.trackId
      let observation = tracked.observation
      let quality = qualityGate.evaluate(observation: observation, sampleBuffer: sampleBuffer, thresholds: thresholds)
      guard quality.accepted else {
        rejectedByQuality += 1
        emitEvent(
          trackId: trackId,
          matched: nil,
          similarity: 0,
          confidence: 0,
          quality: quality.score,
          box: observation.boundingBox,
          accepted: false,
          rejectReason: quality.reason,
          topCandidates: [],
          detectionMs: detectionMs,
          embeddingMs: 0,
          matchingMs: 0
        )
        continue
      }

      guard let faceImage = cropFace(observation: observation, sampleBuffer: sampleBuffer) else {
        continue
      }

      let tEmbedding = Date()
      let embedding: [Float]
      do {
        embedding = try embeddingModel.embedding(from: faceImage)
      } catch {
        continue
      }
      let embeddingMs = Date().timeIntervalSince(tEmbedding) * 1000

      let tMatching = Date()
      recognitionAttempts += 1
      let topCandidates = matcher.topCandidates(for: embedding, topK: 3)
      let best = topCandidates.first
      let matchingMs = Date().timeIntervalSince(tMatching) * 1000

      if let matched = best {
        if shouldSuppress(trackId: trackId, studentId: matched.studentId, now: now) {
          duplicatePrevented += 1
          continue
        }
        if matched.similarity >= thresholds.autoMarkThreshold {
          successfulMatches += 1
        }
      }

      emitEvent(
        trackId: trackId,
        matched: best,
        similarity: best?.similarity ?? 0.0,
        confidence: best?.confidence ?? 0.0,
        quality: quality.score,
        box: observation.boundingBox,
        accepted: true,
        rejectReason: nil,
        topCandidates: topCandidates,
        detectionMs: detectionMs,
        embeddingMs: embeddingMs,
        matchingMs: matchingMs
      )
    }
  }

  private func detectFaces(sampleBuffer: CMSampleBuffer) -> [(trackId: Int, observation: VNFaceObservation)] {
    let detectRequest = VNDetectFaceRectanglesRequest()
    do {
      if #available(iOS 14.0, *) {
        let imageRequestHandler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored, options: [:])
        try imageRequestHandler.perform([detectRequest])
      } else {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
          return []
        }
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        try imageRequestHandler.perform([detectRequest])
      }
    } catch {
      return []
    }
    guard let detections = detectRequest.results as? [VNFaceObservation], !detections.isEmpty else {
      trackedObservations.removeAll()
      return []
    }

    // Lightweight matching by nearest box center to keep track IDs stable across frames.
    var assignments: [(Int, VNFaceObservation)] = []
    var usedTrackIds = Set<Int>()
    for face in detections {
      let centerX = face.boundingBox.midX
      let centerY = face.boundingBox.midY
      var chosenTrackId: Int?
      var bestDistance: CGFloat = 999
      for (trackId, prev) in trackedObservations {
        if usedTrackIds.contains(trackId) { continue }
        let dx = prev.boundingBox.midX - centerX
        let dy = prev.boundingBox.midY - centerY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDistance {
          bestDistance = dist
          chosenTrackId = trackId
        }
      }
      if let trackId = chosenTrackId, bestDistance < 0.18 {
        assignments.append((trackId, face))
        usedTrackIds.insert(trackId)
      } else {
        let trackId = nextTrackId
        nextTrackId += 1
        assignments.append((trackId, face))
        usedTrackIds.insert(trackId)
      }
    }

    trackedObservations = Dictionary(uniqueKeysWithValues: assignments.map { ($0.0, $0.1 as VNDetectedObjectObservation) })
    return assignments.map { (trackId: $0.0, observation: $0.1) }
  }

  private func shouldSuppress(trackId: Int, studentId: String, now: Date) -> Bool {
    if let lastTrack = trackLastDecisionAt[trackId], now.timeIntervalSince(lastTrack) < Double(thresholds.trackCooldownSeconds) {
      return true
    }
    if let lastStudent = studentLastMarkAt[studentId], now.timeIntervalSince(lastStudent) < Double(thresholds.studentCooldownSeconds) {
      return true
    }
    trackLastDecisionAt[trackId] = now
    studentLastMarkAt[studentId] = now
    return false
  }

  private func cropFace(observation: VNFaceObservation, sampleBuffer: CMSampleBuffer) -> CGImage? {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let width = ciImage.extent.width
    let height = ciImage.extent.height

    let box = observation.boundingBox
    let rect = CGRect(
      x: box.origin.x * width,
      y: (1 - box.origin.y - box.size.height) * height,
      width: box.size.width * width,
      height: box.size.height * height
    )
    let expanded = rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15).intersection(ciImage.extent)
    guard !expanded.isNull else { return nil }
    return ciContext.createCGImage(ciImage, from: expanded)
  }

  private func emitEvent(
    trackId: Int,
    matched: MatchCandidate?,
    similarity: Double,
    confidence: Double,
    quality: Double,
    box: CGRect,
    accepted: Bool,
    rejectReason: String?,
    topCandidates: [MatchCandidate],
    detectionMs: Double,
    embeddingMs: Double,
    matchingMs: Double
  ) {
    if debugMode {
      NSLog(
        "face_pipeline frame=%d attempts=%d matches=%d rejected=%d dup=%d detect=%.2f embed=%.2f match=%.2f",
        frameCount,
        recognitionAttempts,
        successfulMatches,
        rejectedByQuality,
        duplicatePrevented,
        detectionMs,
        embeddingMs,
        matchingMs
      )
    }

    let payload = RecognitionEventPayload(
      trackId: trackId,
      matchedStudentId: matched?.studentId,
      matchedStudentName: matched?.studentName,
      confidence: confidence,
      similarity: similarity,
      faceBox: FaceBox(x: box.origin.x, y: box.origin.y, w: box.width, h: box.height),
      qualityScore: quality,
      timestamp: ISO8601DateFormatter().string(from: Date()),
      imageAcceptedForRecognition: accepted,
      reasonIfRejected: rejectReason,
      topCandidates: topCandidates.map {
        RecognitionCandidatePayload(
          studentId: $0.studentId,
          studentName: $0.studentName,
          similarity: $0.similarity,
          confidence: $0.confidence
        )
      }
    )
    DispatchQueue.main.async { [onEvent] in
      onEvent(payload)
    }
  }
}

extension FaceRecognitionPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    processingQueue.async { [weak self] in
      self?.processFrame(sampleBuffer)
    }
  }
}
