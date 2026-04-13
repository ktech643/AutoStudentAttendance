import '../../core/config/attendance_thresholds.dart';
import '../../core/models/recognition_event.dart';
import '../../core/models/student.dart';
import 'face_attendance_platform_service.dart';
import 'simulated_recognition_service.dart';

abstract class RecognitionSource {
  Stream<RecognitionEvent> events();
  Future<void> start(AttendanceThresholds thresholds);
  Future<void> stop();

  /// Pushes enrolled embeddings to the recognition engine so matching can be
  /// done on-device without network calls during recognition.
  /// Pass an empty list to clear all enrolled templates.
  Future<void> loadEnrolledEmbeddings(List<Map<String, dynamic>> embeddings);
}

class PlatformRecognitionSource implements RecognitionSource {
  PlatformRecognitionSource(this._platformService);

  final FaceAttendancePlatformService _platformService;

  @override
  Stream<RecognitionEvent> events() => _platformService.recognitionEvents();

  @override
  Future<void> start(AttendanceThresholds thresholds) async {
    await _platformService.startRecognition(thresholds: thresholds);
  }

  @override
  Future<void> stop() async {
    await _platformService.stopRecognition();
  }

  @override
  Future<void> loadEnrolledEmbeddings(List<Map<String, dynamic>> embeddings) async {
    await _platformService.loadEnrolledEmbeddings(embeddings);
  }
}

class SimulatedRecognitionSource implements RecognitionSource {
  SimulatedRecognitionSource(this._simulatedService, this._studentPool);

  final SimulatedRecognitionService _simulatedService;
  final List<Student> Function() _studentPool;

  @override
  Stream<RecognitionEvent> events() => _simulatedService.stream();

  @override
  Future<void> start(AttendanceThresholds thresholds) async {
    _simulatedService.setStudentPool(_studentPool());
    _simulatedService.start();
  }

  @override
  Future<void> stop() async => _simulatedService.stop();

  @override
  Future<void> loadEnrolledEmbeddings(List<Map<String, dynamic>> embeddings) async {
    // Simulated source does not use embeddings; its student pool is set in start().
  }
}
