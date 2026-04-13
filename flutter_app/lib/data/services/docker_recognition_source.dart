import 'dart:async';
import 'dart:typed_data';

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
/// Uses [startImageStream] — frames are grabbed from the live video feed and
/// converted to JPEG in a background isolate.  This avoids the camera
/// shutter/blink that [CameraController.takePicture] would cause.
class DockerRecognitionSource implements RecognitionSource {
  DockerRecognitionSource({required Dio dio}) : _dio = dio;

  final Dio _dio;

  final _controller = StreamController<RecognitionEvent>.broadcast();
  CameraController? _camera;
  Timer? _pollTimer;
  bool _processing = false;
  int _trackSeq = 0;

  // Latest raw frame from the image stream (not yet converted).
  CameraImage? _latestFrame;

  /// Notifies the UI when the camera controller is ready for preview.
  /// Null while the camera is not yet initialised or after stop().
  final cameraNotifier = ValueNotifier<CameraController?>(null);

  @override
  Stream<RecognitionEvent> events() => _controller.stream;

  @override
  Future<void> start(AttendanceThresholds thresholds) async {
    await _initCamera();
    // Poll at ~2 FPS — enough for smooth recognition without overloading Docker.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _processLatestFrame());
  }

  @override
  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    cameraNotifier.value = null;
    try { await _camera?.stopImageStream(); } catch (_) {}
    await _camera?.dispose();
    _camera = null;
    _latestFrame = null;
  }

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
      ResolutionPreset.medium, // 640×480 — good balance of speed vs accuracy
      enableAudio: false,
    );
    await _camera!.initialize();
    // Buffer the latest frame; we only process on the poll timer.
    await _camera!.startImageStream((frame) {
      _latestFrame = frame;
    });
    // Signal to the UI that the preview is ready.
    cameraNotifier.value = _camera;
  }

  Future<void> _processLatestFrame() async {
    if (_processing) return;
    final frame = _latestFrame;
    if (frame == null) return;
    _processing = true;
    try {
      final jpeg = await compute(_convertToJpeg, _FrameData(
        width: frame.width,
        height: frame.height,
        format: frame.format.group,
        planes: frame.planes.map((p) => _PlaneData(
          bytes: p.bytes,
          bytesPerRow: p.bytesPerRow,
          bytesPerPixel: p.bytesPerPixel ?? 1,
        )).toList(),
      ));
      if (jpeg != null) await _recognize(jpeg);
    } finally {
      _processing = false;
    }
  }

  Future<void> _recognize(Uint8List jpeg) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/recognize',
        data: FormData.fromMap({
          'image': MultipartFile.fromBytes(
            jpeg,
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
        final confidence = (r['confidence'] as num?)?.toDouble() ?? 0.0;
        final bbox = r['bbox'] as List<dynamic>?;
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
      // Network transient — skip frame silently.
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate-safe data classes + conversion function
// ---------------------------------------------------------------------------

class _PlaneData {
  _PlaneData({required this.bytes, required this.bytesPerRow, required this.bytesPerPixel});
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class _FrameData {
  _FrameData({required this.width, required this.height, required this.format, required this.planes});
  final int width;
  final int height;
  final ImageFormatGroup format;
  final List<_PlaneData> planes;
}

/// Runs in a compute isolate — converts a raw CameraImage to JPEG bytes.
Uint8List? _convertToJpeg(_FrameData data) {
  try {
    img.Image image;

    if (data.format == ImageFormatGroup.bgra8888) {
      // iOS: single BGRA plane
      image = img.Image.fromBytes(
        width: data.width,
        height: data.height,
        bytes: data.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
        numChannels: 4,
      );
    } else if (data.format == ImageFormatGroup.yuv420) {
      // Android / some iOS configs: YUV 4:2:0
      final yPlane = data.planes[0];
      final uPlane = data.planes[1];
      final vPlane = data.planes[2];
      final w = data.width;
      final h = data.height;
      image = img.Image(width: w, height: h, numChannels: 3);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final yv = yPlane.bytes[y * yPlane.bytesPerRow + x];
          final uvX = x >> 1;
          final uvY = y >> 1;
          final uv = uvY * uPlane.bytesPerRow + uvX * uPlane.bytesPerPixel;
          final u = uPlane.bytes[uv] - 128;
          final v = vPlane.bytes[uv] - 128;
          final r = (yv + 1.402 * v).clamp(0, 255).toInt();
          final g = (yv - 0.344136 * u - 0.714136 * v).clamp(0, 255).toInt();
          final b = (yv + 1.772 * u).clamp(0, 255).toInt();
          image.setPixelRgb(x, y, r, g, b);
        }
      }
    } else {
      return null; // Unsupported format
    }

    // Downsample to 480×360 to keep upload size small.
    final resized = img.copyResize(image, width: 480, height: 360,
        interpolation: img.Interpolation.average);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  } catch (_) {
    return null;
  }
}
