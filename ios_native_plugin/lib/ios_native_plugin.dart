library ios_face_attendance_plugin;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class FaceAttendanceNativeBridge {
  FaceAttendanceNativeBridge._();

  static const MethodChannel _methodChannel = MethodChannel('face_attendance/methods');
  static const EventChannel _eventChannel = EventChannel('face_attendance/events');

  static Future<void> startRecognition(Map<String, dynamic> thresholds) {
    return _methodChannel.invokeMethod<void>('startRecognition', {'thresholds': thresholds});
  }

  static Future<void> stopRecognition() {
    return _methodChannel.invokeMethod<void>('stopRecognition');
  }

  static Stream<dynamic> recognitionEvents() {
    return _eventChannel.receiveBroadcastStream();
  }
}

/// Shows the native AVCaptureSession preview via a UiKitView PlatformView.
///
/// Use this in kiosk mode instead of the Flutter `camera` package CameraPreview —
/// the native recognition pipeline already owns the AVCaptureSession, so running
/// a second CameraController alongside it conflicts on iOS.
class NativeCameraPreview extends StatelessWidget {
  const NativeCameraPreview({super.key});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    return UiKitView(
      viewType: 'face_attendance/camera_preview',
      layoutDirection: TextDirection.ltr,
      creationParams: const <String, dynamic>{},
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
    );
  }
}
