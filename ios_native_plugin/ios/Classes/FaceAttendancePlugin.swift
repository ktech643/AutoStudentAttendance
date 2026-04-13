import Flutter
import UIKit

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
      stopRecognition()
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
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func startRecognition(thresholds: RecognitionThresholds) {
    if pipeline == nil {
      let embeddingModel = MockFaceEmbeddingModel()
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
    pipeline?.setThresholds(thresholds)
    pipeline?.start()
  }

  private func stopRecognition() {
    pipeline?.stop()
  }

  private func extractThresholds(from arguments: Any?) -> RecognitionThresholds? {
    guard let args = arguments as? [String: Any] else { return nil }
    let map: [String: Any]
    if let nested = args["thresholds"] as? [String: Any] {
      map = nested
    } else {
      map = args
    }
    return RecognitionThresholds(
      autoMarkThreshold: map["auto_mark_threshold"] as? Double ?? 0.72,
      reviewThreshold: map["review_threshold"] as? Double ?? 0.62,
      consecutiveFramesRequired: map["consecutive_frames_required"] as? Int ?? 3,
      minStableTrackingSeconds: map["min_stable_tracking_seconds"] as? Double ?? 1.0,
      studentCooldownSeconds: map["student_cooldown_seconds"] as? Int ?? 300,
      trackCooldownSeconds: map["track_cooldown_seconds"] as? Int ?? 10,
      minFaceSizeRatio: map["min_face_size_ratio"] as? Double ?? 0.10,
      minBlurScore: map["min_blur_score"] as? Double ?? 100.0,
      minBrightness: map["min_brightness"] as? Double ?? 35.0,
      maxAbsYaw: map["max_abs_yaw"] as? Double ?? 20.0,
      maxAbsPitch: map["max_abs_pitch"] as? Double ?? 20.0,
      debugMode: map["debug_mode"] as? Bool ?? false
    )
  }
}
