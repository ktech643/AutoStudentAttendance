import 'package:flutter/services.dart';

import '../../core/config/attendance_thresholds.dart';
import '../../core/models/recognition_event.dart';

class FaceAttendancePlatformService {
  FaceAttendancePlatformService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ?? const MethodChannel('face_attendance/methods'),
        _eventChannel = eventChannel ?? const EventChannel('face_attendance/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<RecognitionEvent> recognitionEvents() {
    return _eventChannel.receiveBroadcastStream().map((dynamic raw) {
      final map = _castMap(raw);
      return RecognitionEvent.fromJson(map);
    });
  }

  Future<void> startRecognition({required AttendanceThresholds thresholds}) async {
    await _methodChannel.invokeMethod<void>('startRecognition', {
      'thresholds': thresholds.toPlatformMap(),
    });
  }

  Future<void> stopRecognition() async {
    await _methodChannel.invokeMethod<void>('stopRecognition');
  }

  Future<void> setThresholds(AttendanceThresholds thresholds) async {
    await _methodChannel.invokeMethod<void>('setThresholds', thresholds.toPlatformMap());
  }

  Future<void> reloadEmbeddings() async {
    await _methodChannel.invokeMethod<void>('reloadEmbeddings');
  }

  Future<void> setDebugMode(bool value) async {
    await _methodChannel.invokeMethod<void>('setDebugMode', {'enabled': value});
  }

  Map<String, dynamic> _castMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    throw PlatformException(code: 'invalid_payload', message: 'Recognition payload is not a map');
  }
}
