import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/attendance_thresholds.dart';
import '../../core/models/recognition_event.dart';
import '../../core/models/recognition_candidate.dart';
import 'recognition_source.dart';

/// RecognitionSource backed by the Docker AttendX API.
///
/// Captures frames from the front camera at ~3 FPS and POSTs each JPEG to
/// `POST /recognize`.  Docker runs InsightFace server-side, returns matched
/// students, and marks attendance automatically.
///
/// The camera session is exclusive — no second session should be active on iOS
/// while this source is running.
class DockerRecognitionSource implements RecognitionSource {
  DockerRecognitionSource({required Dio dio}) : _dio = dio;

  final Dio _dio;

  final _controller = StreamController<RecognitionEvent>.broadcast();
  CameraController? _camera;
  Timer? _pollTimer;
  bool _processing = false;
  int _trackSeq = 0;

  @override
  Stream<RecognitionEvent> events() => _controller.stream;

  @override
  Future<void> start(AttendanceThresholds thresholds) async {
    await _initCamera();
    // Poll every 600 ms (~1-2 useful frames/s accounting for network latency).
    _pollTimer = Timer.periodic(const Duration(milliseconds: 600), (_) => _sendFrame());
  }

  @override
  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _camera?.stopImageStream().catchError((_) {});
    await _camera?.dispose();
    _camera = null;
  }

  // DockerRecognitionSource does not use on-device embeddings.
  @override
  Future<void> loadEnrolledEmbeddings(List<Map<String, dynamic>> embeddings) async {}

  // ---------------------------------------------------------------------------

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camera = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _camera!.initialize();
  }

  Future<void> _sendFrame() async {
    if (_processing || _camera == null || !(_camera!.value.isInitialized)) return;
    _processing = true;
    try {
      final file = await _camera!.takePicture();
      final bytes = await file.readAsBytes();
      await _recognize(bytes);
    } catch (_) {
      // Camera not ready or network error — skip frame.
    } finally {
      _processing = false;
    }
  }

  Future<void> _recognize(Uint8List jpegBytes) async {
    try {
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(
          jpegBytes,
          filename: 'frame.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      final response = await _dio.post<Map<String, dynamic>>(
        '/recognize',
        data: formData,
      );

      final data = response.data;
      if (data == null) return;

      final recognized = (data['recognized'] as List<dynamic>?) ?? [];
      final totalFaces = (data['total_faces_detected'] as int?) ?? 0;
      final now = DateTime.now();

      if (recognized.isEmpty) {
        // Emit a "no match" event so the overlay can reflect detection without match.
        if (totalFaces > 0) {
          _controller.add(RecognitionEvent(
            trackId: ++_trackSeq,
            confidence: 0,
            similarity: 0,
            qualityScore: 0.5,
            timestamp: now,
            imageAcceptedForRecognition: true,
            reasonIfRejected: null,
          ));
        }
        return;
      }

      for (final r in recognized.whereType<Map<String, dynamic>>()) {
        final confidence = (r['confidence'] as num?)?.toDouble() ?? 0.0;
        final bbox = r['bbox'] as List<dynamic>?; // [x, y, w, h] in pixels

        // Normalise bbox to 0-1 if present. Docker returns pixel coords for a
        // 640×480 (medium preset) image — normalise assuming 640×480.
        Map<String, dynamic>? faceBox;
        if (bbox != null && bbox.length == 4) {
          const w = 640.0, h = 480.0;
          faceBox = {
            'x': (bbox[0] as num).toDouble() / w,
            'y': (bbox[1] as num).toDouble() / h,
            'w': (bbox[2] as num).toDouble() / w,
            'h': (bbox[3] as num).toDouble() / h,
          };
        }

        _controller.add(RecognitionEvent(
          trackId: ++_trackSeq,
          matchedStudentId: r['student_id'] as String?,
          matchedStudentName: r['name'] as String?,
          confidence: confidence,
          similarity: confidence,
          qualityScore: confidence,
          faceBox: faceBox,
          timestamp: now,
          imageAcceptedForRecognition: true,
          topCandidates: [
            if (r['student_id'] != null)
              RecognitionCandidate(
                studentId: r['student_id'] as String,
                studentName: r['name'] as String? ?? '',
                similarity: confidence,
                confidence: confidence,
              ),
          ],
        ));
      }
    } on DioException {
      // Network failure — skip silently.
    }
  }
}
