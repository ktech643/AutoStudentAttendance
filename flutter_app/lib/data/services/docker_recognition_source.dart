import 'dart:async';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/config/attendance_thresholds.dart';
import '../../core/models/recognition_candidate.dart';
import '../../core/models/recognition_event.dart';
import 'recognition_source.dart';

/// RecognitionSource backed by the Docker AttendX API (InsightFace server-side).
///
/// Frames are grabbed from [startImageStream] and converted to JPEG in a
/// background isolate — no shutter sound or camera blink.
///
/// Key design decisions
/// ────────────────────
/// • **Stable trackId per student** — the same student always maps to the same
///   integer trackId.  This lets the decision engine accumulate
///   `acceptedFrameCount` across frames and apply cooldowns correctly.
///   Without this, every event got a fresh id → engine restarted every frame
///   → attendance was recorded on every single 500 ms tick.
/// • **Skip `already_marked`** — when Docker's `/recognize` says the student
///   was already marked within its own cooldown window we skip emitting an
///   event entirely.  This prevents the decision engine from creating an
///   extra review entry for what is effectively a duplicate hit.
class DockerRecognitionSource implements RecognitionSource {
  DockerRecognitionSource({required Dio dio}) : _dio = dio;

  final Dio _dio;

  final _controller = StreamController<RecognitionEvent>.broadcast();
  CameraController? _camera;
  Timer? _pollTimer;
  bool _processing = false;
  int _trackSeq = 0;

  // Stable trackId per student_id — persists for the lifetime of the source.
  final _studentTrackIds = <String, int>{};

  // Latest raw frame from the image stream (not yet converted).
  CameraImage? _latestFrame;

  /// Notifies the UI when the camera controller is ready for preview.
  /// Null while the camera is not yet initialised or after [stop].
  final cameraNotifier = ValueNotifier<CameraController?>(null);

  // ---------------------------------------------------------------------------

  @override
  Stream<RecognitionEvent> events() => _controller.stream;

  @override
  Future<void> start(AttendanceThresholds thresholds) async {
    await _initCamera();
    // ~2 FPS — enough for smooth recognition without overloading Docker.
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _processLatestFrame(),
    );
  }

  @override
  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    cameraNotifier.value = null;
    try {
      await _camera?.stopImageStream();
    } catch (_) {}
    await _camera?.dispose();
    _camera = null;
    _latestFrame = null;
  }

  @override
  Future<void> loadEnrolledEmbeddings(
      List<Map<String, dynamic>> embeddings) async {}

  // ---------------------------------------------------------------------------

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camera = CameraController(
      front,
      ResolutionPreset.medium, // 640×480 — speed vs accuracy balance
      enableAudio: false,
    );
    await _camera!.initialize();
    await _camera!.startImageStream((frame) => _latestFrame = frame);
    cameraNotifier.value = _camera;
  }

  Future<void> _processLatestFrame() async {
    if (_processing) return;
    final frame = _latestFrame;
    if (frame == null) return;
    _processing = true;
    try {
      final result = await compute(
        _convertToJpeg,
        _FrameData(
          width: frame.width,
          height: frame.height,
          format: frame.format.group,
          planes: frame.planes
              .map((p) => _PlaneData(
                    bytes: p.bytes,
                    bytesPerRow: p.bytesPerRow,
                    bytesPerPixel: p.bytesPerPixel ?? 1,
                  ))
              .toList(),
        ),
      );
      if (result != null) await _recognize(result);
    } finally {
      _processing = false;
    }
  }

  int _stableTrackId(String? studentId) {
    if (studentId == null || studentId.isEmpty) return ++_trackSeq;
    return _studentTrackIds.putIfAbsent(studentId, () => ++_trackSeq);
  }

  Future<void> _recognize(_JpegResult result) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/recognize',
        data: FormData.fromMap({
          'image': MultipartFile.fromBytes(
            result.jpeg,
            filename: 'frame.jpg',
            contentType: DioMediaType('image', 'jpeg'),
          ),
        }),
      );
      final data = response.data;
      if (data == null) return;

      final recognized = (data['recognized'] as List<dynamic>?) ?? [];
      final totalFaces = (data['total_faces_detected'] as int?) ?? 0;
      final now = DateTime.now();

      // Unknown face in frame — emit a low-confidence unmatched event so the
      // overlay shows the bounding box.
      if (recognized.isEmpty && totalFaces > 0) {
        _controller.add(RecognitionEvent(
          trackId: ++_trackSeq,
          confidence: 0,
          similarity: 0,
          qualityScore: 0.5,
          timestamp: now,
          imageAcceptedForRecognition: true,
        ));
        return;
      }

      for (final r in recognized.whereType<Map<String, dynamic>>()) {
        // Docker already marked attendance within its own cooldown window.
        // Skip to avoid the decision engine creating a duplicate review entry.
        final alreadyMarked = r['already_marked'] as bool? ?? false;
        if (alreadyMarked) continue;

        final studentId = r['student_id'] as String?;
        final confidence = (r['confidence'] as num?)?.toDouble() ?? 0.0;

        // Normalise bbox using the actual image dimensions Docker received.
        final bbox = r['bbox'] as List<dynamic>?;
        Map<String, dynamic>? faceBox;
        if (bbox != null && bbox.length >= 4) {
          final imgW = result.width.toDouble();
          final imgH = result.height.toDouble();
          faceBox = {
            'x': (bbox[0] as num).toDouble() / imgW,
            'y': (bbox[1] as num).toDouble() / imgH,
            'w': (bbox[2] as num).toDouble() / imgW,
            'h': (bbox[3] as num).toDouble() / imgH,
          };
        }

        _controller.add(RecognitionEvent(
          trackId: _stableTrackId(studentId), // stable per student
          matchedStudentId: studentId,
          matchedStudentName: r['name'] as String?,
          confidence: confidence,
          similarity: confidence,
          qualityScore: confidence,
          faceBox: faceBox,
          timestamp: now,
          imageAcceptedForRecognition: true,
          topCandidates: [
            if (studentId != null)
              RecognitionCandidate(
                studentId: studentId,
                studentName: r['name'] as String? ?? '',
                similarity: confidence,
                confidence: confidence,
              ),
          ],
        ));
      }
    } on DioException {
      // Network transient — skip frame silently.
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate-safe data classes + conversion function
// ---------------------------------------------------------------------------

class _PlaneData {
  _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class _FrameData {
  _FrameData({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
  });
  final int width;
  final int height;
  final ImageFormatGroup format;
  final List<_PlaneData> planes;
}

/// Carries the encoded JPEG and the actual pixel dimensions of the sent image
/// so the caller can normalise bounding-box coordinates correctly.
class _JpegResult {
  const _JpegResult(this.jpeg, this.width, this.height);
  final Uint8List jpeg;
  final int width;
  final int height;
}

/// Runs in a compute isolate — converts a raw CameraImage to JPEG bytes.
///
/// **Rotation**: iOS delivers camera frames in landscape orientation (raw
/// sensor buffer, width > height) even when the device is held in portrait.
/// We rotate 90° clockwise so the JPEG is upright — this is required for
/// Docker's InsightFace detector to find the face correctly.
_JpegResult? _convertToJpeg(_FrameData data) {
  try {
    img.Image image;

    if (data.format == ImageFormatGroup.bgra8888) {
      image = img.Image.fromBytes(
        width: data.width,
        height: data.height,
        bytes: data.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
        numChannels: 4,
      );
    } else if (data.format == ImageFormatGroup.yuv420) {
      final yPlane = data.planes[0];
      final uPlane = data.planes[1];
      final vPlane = data.planes[2];
      final w = data.width, h = data.height;
      image = img.Image(width: w, height: h, numChannels: 3);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final yv = yPlane.bytes[y * yPlane.bytesPerRow + x];
          final uvIdx =
              (y >> 1) * uPlane.bytesPerRow + (x >> 1) * uPlane.bytesPerPixel;
          final u = uPlane.bytes[uvIdx] - 128;
          final v = vPlane.bytes[uvIdx] - 128;
          image.setPixelRgb(
            x, y,
            (yv + 1.402 * v).clamp(0, 255).toInt(),
            (yv - 0.344136 * u - 0.714136 * v).clamp(0, 255).toInt(),
            (yv + 1.772 * u).clamp(0, 255).toInt(),
          );
        }
      }
    } else {
      return null;
    }

    // Rotate landscape buffer to portrait so faces are upright.
    if (image.width > image.height) {
      image = img.copyRotate(image, angle: 90);
    }

    // Resize to max 480 px on the longest edge — keeps upload small.
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > 480) {
      final scale = 480.0 / longest;
      image = img.copyResize(
        image,
        width: (image.width * scale).round(),
        height: (image.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }

    final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 82));
    return _JpegResult(jpeg, image.width, image.height);
  } catch (_) {
    return null;
  }
}
