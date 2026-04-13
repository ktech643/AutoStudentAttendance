import 'package:flutter/foundation.dart';
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
      return RecognitionEvent.fromJson(_castMap(raw));
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

  /// Sends enrolled embeddings (fetched from the backend) to the native plugin
  /// so it can perform on-device face matching without network calls.
  ///
  /// [embeddings] is a list of maps with keys:
  ///   studentId, studentName, rollNumber, vector ([double])
  Future<void> loadEnrolledEmbeddings(List<Map<String, dynamic>> embeddings) async {
    await _methodChannel.invokeMethod<void>('loadEnrolledEmbeddings', {
      'embeddings': embeddings,
    });
  }

  /// Sends a JPEG image to the native plugin, detects the face in it, and
  /// returns the embedding vector as [List<double>].
  ///
  /// Throws a [PlatformException] if no face is found or the model fails.
  /// Returns an empty list on web (native model not available).
  Future<List<double>> extractEmbeddingFromImage(Uint8List jpegBytes) async {
    if (kIsWeb) return const [];
    final raw = await _methodChannel.invokeMethod<List<dynamic>>(
      'extractEmbeddingFromImage',
      {'jpegBytes': jpegBytes},
    );
    return raw?.cast<double>() ?? const [];
  }

  Map<String, dynamic> _castMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    throw PlatformException(code: 'invalid_payload', message: 'Recognition payload is not a map');
  }
}
