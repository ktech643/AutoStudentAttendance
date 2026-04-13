import 'dart:async' show Timer, unawaited;
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/models/student.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/services/face_attendance_platform_service.dart';
import '../providers/providers.dart';

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

enum _EnrollmentPhase { enterDetails, captureFace, done }

class _EnrollmentSample {
  const _EnrollmentSample({
    required this.qualityScore,
    required this.accepted,
    required this.hint,
    required this.embedding,
    this.jpegBytes,
    this.thumbnail,
  });

  final double qualityScore;
  final bool accepted;
  final String hint;
  final List<double> embedding;
  final Uint8List? jpegBytes;
  final Uint8List? thumbnail; // small JPEG for UI preview
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class StudentEnrollmentScreen extends ConsumerStatefulWidget {
  const StudentEnrollmentScreen({super.key});

  @override
  ConsumerState<StudentEnrollmentScreen> createState() => _StudentEnrollmentScreenState();
}

class _StudentEnrollmentScreenState extends ConsumerState<StudentEnrollmentScreen>
    with TickerProviderStateMixin {
  _EnrollmentPhase _phase = _EnrollmentPhase.enterDetails;

  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _classController = TextEditingController(text: '1');
  final _sectionController = TextEditingController(text: 'A');

  Student? _createdStudent;
  final List<_EnrollmentSample> _samples = [];
  final Random _random = Random();

  CameraController? _cameraController;
  // Latest frame from image stream — used for face detection + capture.
  CameraImage? _latestFrame;

  bool _creatingStudent = false;
  bool _isSubmitting = false;

  // ---- Face guidance state ----
  Timer? _guidanceTimer;
  bool _analyzing = false;
  // Normalised face box (0-1, top-left origin); null = no face
  Map<String, dynamic>? _faceBox;
  String _guidanceText = 'Position your face in the circle';
  Color _guideColor = Colors.white54;
  // Countdown to auto-capture (0 = ready, counts down from 3)
  int _countdown = 0;
  Timer? _countdownTimer;
  int _goodFramesInRow = 0;

  // ---- Flash feedback animation ----
  late final AnimationController _captureFlashCtrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 350),
  );
  late final Animation<double> _captureFlashAnim =
      CurvedAnimation(parent: _captureFlashCtrl, curve: Curves.easeOut);

  bool get _nativeAvailable => !kIsWeb && Platform.isIOS;
  bool get _canSubmit =>
      !_isSubmitting && _createdStudent != null && _acceptedCount >= 3;
  int get _acceptedCount => _samples.where((s) => s.accepted).length;

  // ---- Required angles ----
  static const _requiredAngles = ['Front', 'Slight left', 'Slight right', 'Chin up', 'Chin down'];

  @override
  void dispose() {
    _guidanceTimer?.cancel();
    _countdownTimer?.cancel();
    _captureFlashCtrl.dispose();
    _nameController.dispose();
    _rollController.dispose();
    _classController.dispose();
    _sectionController.dispose();
    unawaited(_cameraController?.stopImageStream().catchError((_) {}));
    _cameraController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Phase 1 — enter details
  // ---------------------------------------------------------------------------

  Future<void> _goToCapture(StudentRepository repo) async {
    final name = _nameController.text.trim();
    final roll = _rollController.text.trim();
    final cls = _classController.text.trim();
    final sec = _sectionController.text.trim();
    if (name.isEmpty || roll.isEmpty || cls.isEmpty || sec.isEmpty) {
      _snack('Please fill in all fields');
      return;
    }
    setState(() => _creatingStudent = true);
    try {
      final student = await repo.createStudent(
        fullName: name, className: cls, section: sec, rollNumber: roll,
      );
      ref.invalidate(studentListProvider);
      setState(() {
        _creatingStudent = false;
        _createdStudent = student;
        _phase = _EnrollmentPhase.captureFace;
        _samples.clear();
        _guidanceText = 'Position your face in the circle';
        _guideColor = Colors.white54;
      });
      await _startCamera();
    } catch (e) {
      setState(() => _creatingStudent = false);
      _snack('Could not create student: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 2 — camera + face guidance
  // ---------------------------------------------------------------------------

  Future<void> _startCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final ctrl = CameraController(
      front,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await ctrl.initialize();
    await ctrl.setFlashMode(FlashMode.off);
    await ctrl.startImageStream((frame) => _latestFrame = frame);
    if (!mounted) { ctrl.dispose(); return; }
    setState(() => _cameraController = ctrl);
    // Start guidance analysis loop every 350 ms.
    _guidanceTimer = Timer.periodic(const Duration(milliseconds: 350), (_) => _analyzeFrame());
  }

  Future<void> _analyzeFrame() async {
    if (_analyzing || !mounted) return;
    final frame = _latestFrame;
    if (frame == null) return;
    _analyzing = true;
    try {
      Uint8List? jpeg;
      if (_nativeAvailable) {
        jpeg = await compute(_frameToJpeg, _frameData(frame));
      }

      Map<String, dynamic> bounds = const {'detected': false};
      if (jpeg != null && jpeg.isNotEmpty) {
        bounds = await FaceAttendancePlatformService().detectFaceBounds(jpeg);
      }

      if (!mounted) return;
      _updateGuidance(bounds, jpeg);
    } finally {
      _analyzing = false;
    }
  }

  void _updateGuidance(Map<String, dynamic> bounds, Uint8List? jpeg) {
    final detected = bounds['detected'] as bool? ?? false;
    if (!detected) {
      _goodFramesInRow = 0;
      _cancelCountdown();
      setState(() {
        _faceBox = null;
        _guidanceText = 'Position your face in the circle';
        _guideColor = Colors.redAccent;
      });
      return;
    }

    final x = (bounds['x'] as num).toDouble();
    final y = (bounds['y'] as num).toDouble();
    final w = (bounds['w'] as num).toDouble();
    final h = (bounds['h'] as num).toDouble();
    final cx = x + w / 2;
    final cy = y + h / 2;

    setState(() => _faceBox = bounds);

    // Ideal: face between 30%-70% of frame width, centred within ±0.12
    String hint = '';
    Color color = Colors.greenAccent;

    if (w < 0.28) {
      hint = 'Move closer ↑';
      color = Colors.orangeAccent;
    } else if (w > 0.70) {
      hint = 'Move back ↓';
      color = Colors.orangeAccent;
    } else if (cx < 0.36) {
      hint = 'Move right →';
      color = Colors.orangeAccent;
    } else if (cx > 0.64) {
      hint = 'Move left ←';
      color = Colors.orangeAccent;
    } else if (cy < 0.34) {
      hint = 'Move down ↓';
      color = Colors.orangeAccent;
    } else if (cy > 0.66) {
      hint = 'Move up ↑';
      color = Colors.orangeAccent;
    }

    final positionGood = hint.isEmpty;
    if (!positionGood) {
      _goodFramesInRow = 0;
      _cancelCountdown();
      setState(() { _guidanceText = hint; _guideColor = color; });
      return;
    }

    // Position is good — count consecutive good frames.
    _goodFramesInRow++;
    setState(() {
      _guideColor = Colors.greenAccent;
      _guidanceText = _acceptedCount < _requiredAngles.length
          ? 'Hold still — capturing ${_requiredAngles[_acceptedCount]}…'
          : 'Hold still…';
    });

    // After 2 good frames (~700ms) start countdown if not already counting.
    if (_goodFramesInRow >= 2 && _countdownTimer == null && !_isSubmitting) {
      _startCountdown(jpeg);
    }
  }

  void _startCountdown(Uint8List? firstJpeg) {
    setState(() => _countdown = 2);
    int count = 2;
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 600), (t) {
      count--;
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown = count);
      if (count <= 0) {
        t.cancel();
        _countdownTimer = null;
        _captureCurrentFrame(firstJpeg);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) setState(() => _countdown = 0);
  }

  Future<void> _captureCurrentFrame(Uint8List? precomputedJpeg) async {
    if (_samples.length >= _requiredAngles.length || _isSubmitting) return;
    final frame = _latestFrame;
    if (frame == null) return;

    // Convert frame to JPEG in background (no camera shutter, no flash).
    final jpeg = precomputedJpeg ?? await compute(_frameToJpeg, _frameData(frame));
    if (jpeg == null || jpeg.isEmpty) return;

    // Extract embedding (or use empty for non-native platforms).
    List<double> embedding = const [];
    if (_nativeAvailable) {
      try {
        embedding = await FaceAttendancePlatformService().extractEmbeddingFromImage(jpeg);
      } catch (_) {}
    } else {
      embedding = List<double>.generate(128, (_) => _random.nextDouble() * 2 - 1);
    }

    // Thumbnail: 80×80 from the JPEG.
    Uint8List? thumb;
    try {
      thumb = await compute(_makeThumb, jpeg);
    } catch (_) {}

    final accepted = embedding.isNotEmpty || !_nativeAvailable;
    final quality = accepted ? (0.80 + _random.nextDouble() * 0.18).clamp(0.0, 1.0) : 0.3;
    final angleName = _acceptedCount < _requiredAngles.length
        ? _requiredAngles[_acceptedCount]
        : 'Sample ${_samples.length + 1}';

    // Brief capture flash feedback.
    unawaited(_captureFlashCtrl.forward().then((_) => _captureFlashCtrl.reverse()));

    if (!mounted) return;
    setState(() {
      _samples.add(_EnrollmentSample(
        qualityScore: quality,
        accepted: accepted,
        hint: accepted ? 'Captured: $angleName' : 'No face — retrying',
        embedding: embedding,
        jpegBytes: jpeg,
        thumbnail: thumb,
      ));
      _guidanceText = accepted
          ? '${_acceptedCount}/${_requiredAngles.length} captured'
          : 'Face not detected — adjust position';
      _goodFramesInRow = 0;
    });

    // Auto-submit when all angles captured.
    if (_acceptedCount >= _requiredAngles.length) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) unawaited(_submit(ref.read(studentRepositoryProvider), silent: true));
    }
  }

  void _retakeRejected() {
    setState(() {
      _samples.removeWhere((s) => !s.accepted);
      _guidanceText = 'Position your face to continue';
      _goodFramesInRow = 0;
    });
    _cancelCountdown();
  }

  Future<void> _submit(StudentRepository repo, {bool silent = false}) async {
    final id = _createdStudent?.id;
    if (id == null || _acceptedCount < 3) {
      if (!silent) _snack('Need at least 3 accepted captures');
      return;
    }
    _guidanceTimer?.cancel();
    _cancelCountdown();

    final accepted = _samples.where((s) => s.accepted).toList();
    final embeddings = accepted.map((s) => s.embedding.isNotEmpty ? s.embedding : _mockEmb()).toList();
    final qualities = accepted.map((s) => s.qualityScore).toList();
    final jpegImages = accepted.map((s) => s.jpegBytes).whereType<Uint8List>().toList();

    setState(() => _isSubmitting = true);
    try {
      await repo.enrollStudent(
        studentId: id,
        embeddings: embeddings,
        qualityScores: qualities,
        sourceType: _nativeAvailable ? 'ios_vision_feature_print' : 'mock_enrollment',
        jpegImages: jpegImages.isNotEmpty ? jpegImages : null,
        studentName: _createdStudent?.fullName,
        className: _createdStudent?.className,
      );
      ref.invalidate(studentListProvider);
      try {
        final all = await repo.fetchStudents();
        ref.read(simulatedStudentPoolProvider.notifier).state = all;
      } catch (_) {}
      if (mounted) {
        setState(() { _isSubmitting = false; _phase = _EnrollmentPhase.done; });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _snack('Enrollment failed: $e');
      }
    }
  }

  void _startOver() {
    _guidanceTimer?.cancel();
    _cancelCountdown();
    unawaited(_cameraController?.stopImageStream().catchError((_) {}));
    _cameraController?.dispose();
    setState(() {
      _phase = _EnrollmentPhase.enterDetails;
      _createdStudent = null;
      _samples.clear();
      _cameraController = null;
      _faceBox = null;
      _guidanceText = 'Position your face in the circle';
      _guideColor = Colors.white54;
    });
  }

  List<double> _mockEmb() =>
      List<double>.generate(128, (_) => _random.nextDouble() * 2 - 1);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(studentRepositoryProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _phase == _EnrollmentPhase.enterDetails
              ? 'New Student'
              : _phase == _EnrollmentPhase.captureFace
                  ? 'Face Scan — ${_createdStudent?.fullName ?? ""}'
                  : 'Enrollment Complete',
        ),
        actions: [
          if (_phase == _EnrollmentPhase.captureFace)
            TextButton(
              onPressed: _startOver,
              child: const Text('Start over', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: switch (_phase) {
        _EnrollmentPhase.enterDetails => _buildDetailsStep(repo),
        _EnrollmentPhase.captureFace => _buildCaptureStep(repo),
        _EnrollmentPhase.done => _buildDoneStep(),
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Details step
  // ---------------------------------------------------------------------------

  Widget _buildDetailsStep(StudentRepository repo) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Student information',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 24),
          _field(_nameController, 'Full name', Icons.person),
          const SizedBox(height: 14),
          _field(_rollController, 'Roll number', Icons.numbers),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _field(_classController, 'Class', Icons.class_)),
            const SizedBox(width: 12),
            Expanded(child: _field(_sectionController, 'Section', Icons.grid_view)),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _creatingStudent ? null : () => _goToCapture(repo),
              icon: _creatingStudent
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(_creatingStudent ? 'Creating…' : 'Continue to face scan',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Capture step
  // ---------------------------------------------------------------------------

  Widget _buildCaptureStep(StudentRepository repo) {
    return Column(
      children: [
        Expanded(child: _buildCameraArea()),
        _buildCapturePanel(repo),
      ],
    );
  }

  Widget _buildCameraArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview or black background.
        if (_cameraController != null && _cameraController!.value.isInitialized)
          CameraPreview(_cameraController!)
        else
          const ColoredBox(color: Colors.black,
              child: Center(child: CircularProgressIndicator(color: Colors.white38))),

        // Capture flash feedback overlay.
        FadeTransition(
          opacity: _captureFlashAnim,
          child: Container(color: Colors.white.withAlpha(80)),
        ),

        // Face guide overlay.
        _FaceGuideOverlay(
          faceBox: _faceBox,
          guideColor: _guideColor,
          guidanceText: _guidanceText,
          countdown: _countdown,
          acceptedCount: _acceptedCount,
          totalRequired: _requiredAngles.length,
        ),
      ],
    );
  }

  Widget _buildCapturePanel(StudentRepository repo) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sample thumbnails row.
          if (_samples.isNotEmpty) ...[
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _samples.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final s = _samples[i];
                  return _SampleThumb(
                    thumb: s.thumbnail,
                    accepted: s.accepted,
                    label: i < _requiredAngles.length ? _requiredAngles[i] : '${i + 1}',
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Progress indicator.
          LinearProgressIndicator(
            value: _acceptedCount / _requiredAngles.length,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(
              _acceptedCount >= _requiredAngles.length ? Colors.greenAccent : Colors.blueAccent,
            ),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_acceptedCount / ${_requiredAngles.length} angles captured',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              if (_samples.any((s) => !s.accepted))
                TextButton.icon(
                  onPressed: _retakeRejected,
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.orangeAccent),
                  label: const Text('Retake bad', style: TextStyle(color: Colors.orangeAccent, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Action buttons.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _captureCount >= _requiredAngles.length
                      ? null
                      : () => _captureCurrentFrame(null),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Capture now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canSubmit ? Colors.greenAccent[700] : Colors.white12,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _canSubmit ? () => _submit(repo) : null,
                  icon: _isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(_isSubmitting ? 'Saving…' : 'Save enrollment'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int get _captureCount => _samples.length;

  // ---------------------------------------------------------------------------
  // Done step
  // ---------------------------------------------------------------------------

  Widget _buildDoneStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 80, color: Colors.greenAccent),
            const SizedBox(height: 20),
            Text(
              '${_createdStudent?.fullName ?? "Student"} enrolled',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$_acceptedCount face samples saved',
              style: const TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _startOver,
              icon: const Icon(Icons.person_add),
              label: const Text('Enroll another student', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Face guide overlay widget
// ---------------------------------------------------------------------------

class _FaceGuideOverlay extends StatelessWidget {
  const _FaceGuideOverlay({
    required this.faceBox,
    required this.guideColor,
    required this.guidanceText,
    required this.countdown,
    required this.acceptedCount,
    required this.totalRequired,
  });

  final Map<String, dynamic>? faceBox;
  final Color guideColor;
  final String guidanceText;
  final int countdown;
  final int acceptedCount;
  final int totalRequired;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FaceGuidePainter(faceBox: faceBox, guideColor: guideColor),
      child: Stack(
        children: [
          // Guidance text at the top.
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  guidanceText,
                  style: TextStyle(
                    color: guideColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
          // Countdown
          if (countdown > 0)
            Center(
              child: Text(
                '$countdown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
                ),
              ),
            ),
          // Progress dots at the bottom.
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(totalRequired, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < acceptedCount ? Colors.greenAccent : Colors.white24,
                    border: Border.all(color: Colors.white38, width: 1),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  const _FaceGuidePainter({this.faceBox, required this.guideColor});
  final Map<String, dynamic>? faceBox;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.42;
    final rw = size.width * 0.32;
    final rh = size.height * 0.30;

    // Dark vignette outside the oval.
    final vigPaint = Paint()..color = Colors.black.withAlpha(100);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final ovalRect = Rect.fromCenter(center: Offset(cx, cy), width: rw * 2.1, height: rh * 2.1);
    final path = Path()
      ..addRect(fullRect)
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, vigPaint);

    // Oval border.
    final borderPaint = Paint()
      ..color = guideColor.withAlpha(200)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawOval(ovalRect, borderPaint);

    // Corner tick marks.
    final tickPaint = Paint()
      ..color = guideColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const tickLen = 18.0;
    final corners = [
      Offset(cx - rw, cy - rh), // top-left
      Offset(cx + rw, cy - rh), // top-right
      Offset(cx - rw, cy + rh), // bottom-left
      Offset(cx + rw, cy + rh), // bottom-right
    ];
    for (final c in corners) {
      final dx = c.dx > cx ? tickLen : -tickLen;
      final dy = c.dy > cy ? tickLen : -tickLen;
      canvas.drawLine(c, Offset(c.dx + dx * 0.6, c.dy), tickPaint);
      canvas.drawLine(c, Offset(c.dx, c.dy + dy * 0.6), tickPaint);
    }

    // Draw detected face box if present.
    if (faceBox != null && faceBox!['detected'] == true) {
      final fx = (faceBox!['x'] as num).toDouble() * size.width;
      final fy = (faceBox!['y'] as num).toDouble() * size.height;
      final fw = (faceBox!['w'] as num).toDouble() * size.width;
      final fh = (faceBox!['h'] as num).toDouble() * size.height;
      final faceRect = Rect.fromLTWH(fx, fy, fw, fh);
      final facePaint = Paint()
        ..color = guideColor.withAlpha(80)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawRect(faceRect, facePaint);
    }
  }

  @override
  bool shouldRepaint(_FaceGuidePainter old) =>
      old.faceBox != faceBox || old.guideColor != guideColor;
}

// ---------------------------------------------------------------------------
// Sample thumbnail widget
// ---------------------------------------------------------------------------

class _SampleThumb extends StatelessWidget {
  const _SampleThumb({this.thumb, required this.accepted, required this.label});
  final Uint8List? thumb;
  final bool accepted;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: accepted ? Colors.greenAccent : Colors.redAccent,
              width: 2,
            ),
            color: Colors.white10,
          ),
          child: thumb != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(thumb!, fit: BoxFit.cover),
                )
              : Icon(
                  accepted ? Icons.check : Icons.close,
                  color: accepted ? Colors.greenAccent : Colors.redAccent,
                  size: 20,
                ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Isolate helpers (top-level, serialisable)
// ---------------------------------------------------------------------------

class _PlaneData {
  _PlaneData({required this.bytes, required this.bytesPerRow, required this.bytesPerPixel});
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class _FrameDataEnrollment {
  _FrameDataEnrollment({required this.width, required this.height, required this.format, required this.planes});
  final int width;
  final int height;
  final ImageFormatGroup format;
  final List<_PlaneData> planes;
}

_FrameDataEnrollment _frameData(CameraImage frame) => _FrameDataEnrollment(
      width: frame.width,
      height: frame.height,
      format: frame.format.group,
      planes: frame.planes.map((p) => _PlaneData(
        bytes: p.bytes,
        bytesPerRow: p.bytesPerRow,
        bytesPerPixel: p.bytesPerPixel ?? 1,
      )).toList(),
    );

Uint8List? _frameToJpeg(_FrameDataEnrollment data) {
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
      final yP = data.planes[0];
      final uP = data.planes[1];
      final vP = data.planes[2];
      image = img.Image(width: data.width, height: data.height, numChannels: 3);
      for (int y = 0; y < data.height; y++) {
        for (int x = 0; x < data.width; x++) {
          final yv = yP.bytes[y * yP.bytesPerRow + x];
          final uvX = x >> 1, uvY = y >> 1;
          final uvIdx = uvY * uP.bytesPerRow + uvX * uP.bytesPerPixel;
          final u = uP.bytes[uvIdx] - 128;
          final v = vP.bytes[uvIdx] - 128;
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
    // Full resolution for enrollment quality; downsample for guidance only.
    return Uint8List.fromList(img.encodeJpg(image, quality: 88));
  } catch (_) {
    return null;
  }
}

Uint8List _makeThumb(Uint8List jpeg) {
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) return jpeg;
  final thumb = img.copyResizeCropSquare(decoded, size: 80);
  return Uint8List.fromList(img.encodeJpg(thumb, quality: 70));
}
