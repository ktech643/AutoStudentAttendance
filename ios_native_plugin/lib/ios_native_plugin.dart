library ios_face_attendance_plugin;

import 'dart:async';

import 'package:flutter/services.dart';

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
