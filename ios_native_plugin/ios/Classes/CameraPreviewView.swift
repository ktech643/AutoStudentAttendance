import AVFoundation
import Flutter
import UIKit

/// FlutterPlatformView that renders the shared AVCaptureSession's preview.
/// Registered under the view type "face_attendance/camera_preview".
final class CameraPreviewPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect, captureSession: AVCaptureSession?) {
    container = UIView(frame: frame)
    container.backgroundColor = .black
    super.init()
    guard let session = captureSession else { return }
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.frame = container.bounds
    layer.videoGravity = .resizeAspectFill
    container.layer.addSublayer(layer)
  }

  func view() -> UIView { container }
}

final class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: FaceAttendancePlugin?

  init(plugin: FaceAttendancePlugin) {
    self.plugin = plugin
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    CameraPreviewPlatformView(frame: frame, captureSession: plugin?.captureSession)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
