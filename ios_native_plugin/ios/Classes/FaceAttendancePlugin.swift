import AVFoundation
import Flutter
import UIKit
import Vision

public class FaceAttendancePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var pipeline: FaceRecognitionPipeline?

  /// Shared session used by both the recognition pipeline and the camera preview PlatformView.
  /// Owned here so the preview works even before recognition is explicitly started.
  let captureSession = AVCaptureSession()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FaceAttendancePlugin()

    let methodChannel = FlutterMethodChannel(name: "face_attendance/methods", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "face_attendance/events", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)

    // Register the native camera preview PlatformView.
    let factory = CameraPreviewFactory(plugin: instance)
    registrar.register(factory, withId: "face_attendance/camera_preview")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {

    case "startRecognition":
      let thresholds = extractThresholds(from: call.arguments) ?? RecognitionThresholds.defaultThresholds
      startRecognition(thresholds: thresholds)
      result(nil)

    case "stopRecognition":
      pipeline?.stop()
      result(nil)

    case "setThresholds":
      let thresholds = extractThresholds(from: call.arguments) ?? RecognitionThresholds.defaultThresholds
      pipeline?.setThresholds(thresholds)
      result(nil)

    case "reloadEmbeddings":
      pipeline?.reloadEmbeddings()
      result(nil)

    case "setDebugMode":
      if let args = call.arguments as? [String: Any], let enabled = args["enabled"] as? Bool {
        pipeline?.setDebugMode(enabled)
      }
      result(nil)

    case "loadEnrolledEmbeddings":
      guard let args = call.arguments as? [String: Any],
            let list = args["embeddings"] as? [[String: Any]] else {
        result(FlutterError(code: "INVALID_ARGS", message: "embeddings list required", details: nil))
        return
      }
      ensurePipeline()
      pipeline?.loadEnrolledEmbeddings(list)
      result(nil)

    case "extractEmbeddingFromImage":
      guard let args = call.arguments as? [String: Any],
            let typedData = args["jpegBytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGS", message: "jpegBytes required", details: nil))
        return
      }
      extractEmbeddingFromJpeg(data: typedData.data, result: result)

    case "detectFaceBounds":
      guard let args = call.arguments as? [String: Any],
            let typedData = args["jpegBytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGS", message: "jpegBytes required", details: nil))
        return
      }
      detectFaceBounds(data: typedData.data, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Private helpers

  private func startRecognition(thresholds: RecognitionThresholds) {
    ensurePipeline()
    pipeline?.setThresholds(thresholds)
    pipeline?.start()
  }

  private func ensurePipeline() {
    guard pipeline == nil else { return }
    let model = FaceEmbeddingModelFactory.make()
    let store = InMemoryEmbeddingStore()
    let matcher = FaceMatcher(embeddingStore: store)
    pipeline = FaceRecognitionPipeline(
      embeddingModel: model,
      matcher: matcher,
      captureSession: captureSession,
      onEvent: { [weak self] event in
        self?.eventSink?(event.toDictionary())
      }
    )
  }

  /// Fast face bounding-box detection on a still JPEG — no embedding extracted.
  /// Returns { detected: Bool, x: Double, y: Double, w: Double, h: Double, quality: Double }
  /// Coordinates are normalised 0-1, top-left origin.
  private func detectFaceBounds(data: Data, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
        DispatchQueue.main.async { result(["detected": false]) }
        return
      }
      let request = VNDetectFaceRectanglesRequest()
      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      try? handler.perform([request])
      guard let face = request.results?.first as? VNFaceObservation else {
        DispatchQueue.main.async { result(["detected": false]) }
        return
      }
      let b = face.boundingBox
      // Vision uses bottom-left origin; convert to top-left for Flutter.
      let payload: [String: Any] = [
        "detected": true,
        "x": Double(b.origin.x),
        "y": Double(1.0 - b.origin.y - b.height),
        "w": Double(b.width),
        "h": Double(b.height),
        "quality": Double(face.confidence),
      ]
      DispatchQueue.main.async { result(payload) }
    }
  }

  /// Runs VNDetectFaceLandmarksRequest on the still JPEG (single pass, no crop needed).
  private func extractEmbeddingFromJpeg(data: Data, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
          DispatchQueue.main.async {
            result(FlutterError(code: "DECODE_FAILED", message: "Cannot decode JPEG", details: nil))
          }
          return
        }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let face = request.results?.first as? VNFaceObservation else {
          DispatchQueue.main.async {
            result(FlutterError(code: "NO_FACE", message: "No face detected in the image", details: nil))
          }
          return
        }

        let model = FaceEmbeddingModelFactory.make()
        let embedding = try model.embedding(from: face)
        DispatchQueue.main.async { result(embedding.map { Double($0) }) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "EMBEDDING_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func extractThresholds(from arguments: Any?) -> RecognitionThresholds? {
    guard let args = arguments as? [String: Any] else { return nil }
    let map: [String: Any] = (args["thresholds"] as? [String: Any]) ?? args
    return RecognitionThresholds(
      autoMarkThreshold: map["auto_mark_threshold"] as? Double ?? 0.74,
      reviewThreshold: map["review_threshold"] as? Double ?? 0.60,
      consecutiveFramesRequired: map["consecutive_frames_required"] as? Int ?? 3,
      minStableTrackingSeconds: map["min_stable_tracking_seconds"] as? Double ?? 1.0,
      studentCooldownSeconds: map["student_cooldown_seconds"] as? Int ?? 300,
      trackCooldownSeconds: map["track_cooldown_seconds"] as? Int ?? 10,
      minFaceSizeRatio: map["min_face_size_ratio"] as? Double ?? 0.08,
      minBlurScore: map["min_blur_score"] as? Double ?? 80.0,
      minBrightness: map["min_brightness"] as? Double ?? 30.0,
      maxAbsYaw: map["max_abs_yaw"] as? Double ?? 25.0,
      maxAbsPitch: map["max_abs_pitch"] as? Double ?? 25.0,
      debugMode: map["debug_mode"] as? Bool ?? false
    )
  }
}
