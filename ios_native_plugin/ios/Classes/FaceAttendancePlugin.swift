import Flutter
import UIKit
import Vision

public class FaceAttendancePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var pipeline: FaceRecognitionPipeline?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(name: "face_attendance/methods", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "face_attendance/events", binaryMessenger: registrar.messenger())
    let instance = FaceAttendancePlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
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
        result(FlutterError(code: "INVALID_ARGS", message: "jpegBytes (FlutterStandardTypedData) required", details: nil))
        return
      }
      extractEmbeddingFromJpeg(data: typedData.data, result: result)

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

  /// Creates the pipeline once; subsequent calls are no-ops.
  private func ensurePipeline() {
    guard pipeline == nil else { return }
    let embeddingModel = FaceEmbeddingModelFactory.make()
    let embeddingStore = InMemoryEmbeddingStore()
    let matcher = FaceMatcher(embeddingStore: embeddingStore)
    pipeline = FaceRecognitionPipeline(
      embeddingModel: embeddingModel,
      matcher: matcher,
      onEvent: { [weak self] event in
        self?.eventSink?(event.toDictionary())
      }
    )
  }

  /// Decodes a JPEG, detects the face, crops it, and extracts a Vision feature print.
  private func extractEmbeddingFromJpeg(data: Data, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
          DispatchQueue.main.async {
            result(FlutterError(code: "DECODE_FAILED", message: "Cannot decode JPEG", details: nil))
          }
          return
        }

        // 1. Detect face in the still image.
        let faceRequest = VNDetectFaceRectanglesRequest()
        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([faceRequest])

        guard let faces = faceRequest.results as? [VNFaceObservation], let face = faces.first else {
          DispatchQueue.main.async {
            result(FlutterError(code: "NO_FACE", message: "No face detected in the image", details: nil))
          }
          return
        }

        // 2. Crop with 15% padding (same margin as live pipeline).
        let box = face.boundingBox
        let faceRect = CGRect(
          x: box.origin.x * imageW,
          y: (1.0 - box.origin.y - box.height) * imageH,
          width: box.width * imageW,
          height: box.height * imageH
        )
        let padded = faceRect
          .insetBy(dx: -faceRect.width * 0.15, dy: -faceRect.height * 0.15)
          .intersection(CGRect(origin: .zero, size: CGSize(width: imageW, height: imageH)))

        guard !padded.isNull, let cropped = cgImage.cropping(to: padded) else {
          DispatchQueue.main.async {
            result(FlutterError(code: "CROP_FAILED", message: "Cannot crop face region", details: nil))
          }
          return
        }

        // 3. Extract embedding with the best available model.
        let model = FaceEmbeddingModelFactory.make()
        let embedding = try model.embedding(from: cropped)

        DispatchQueue.main.async {
          result(embedding.map { Double($0) })
        }
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
