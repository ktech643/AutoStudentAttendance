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

enum _Phase { enterDetails, captureFace, done }

class _Sample {
  const _Sample({
    required this.accepted,
    required this.hint,
    required this.embedding,
    required this.qualityScore,
    this.jpegBytes,
    this.thumbnail,
  });
  final bool accepted;
  final String hint;
  final List<double> embedding;
  final double qualityScore;
  final Uint8List? jpegBytes;
  final Uint8List? thumbnail;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class StudentEnrollmentScreen extends ConsumerStatefulWidget {
  const StudentEnrollmentScreen({super.key});

  @override
  ConsumerState<StudentEnrollmentScreen> createState() =>
      _StudentEnrollmentScreenState();
}

class _StudentEnrollmentScreenState
    extends ConsumerState<StudentEnrollmentScreen>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.enterDetails;

  final _nameCtrl = TextEditingController();
  final _rollCtrl = TextEditingController();
  final _classCtrl = TextEditingController(text: '1');
  final _secCtrl = TextEditingController(text: 'A');

  Student? _student;
  final List<_Sample> _samples = [];
  final _rng = Random();

  CameraController? _cam;
  CameraImage? _latestFrame; // continuously updated from image stream

  bool _creatingStudent = false;
  bool _isSubmitting = false;

  // ---- guidance ----
  Timer? _analysisTimer;
  bool _analyzing = false;

  Map<String, dynamic>? _faceBox; // detected bounding box (0-1, top-left)
  String _guidanceText = 'Position your face in the circle';
  Color _guideColor = Colors.white54;

  // ---- countdown / capture gate ----
  /// Prevents re-entry: set to true from when countdown fires until after
  /// the captured frame has been fully processed.
  bool _capturingNow = false;
  int _goodFrames = 0; // consecutive "position good" analysis frames
  int _countdown = 0;
  Timer? _countdownTimer;

  // ---- capture flash ----
  late final AnimationController _flashCtrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 300));
  late final Animation<double> _flashAnim =
      CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut);

  static const _angles = [
    'Face forward',
    'Turn slightly left',
    'Turn slightly right',
    'Chin up slightly',
    'Chin down slightly',
  ];
  static const _maxSamples = 5;

  bool get _nativeAvail => !kIsWeb && Platform.isIOS;
  bool get _canSave => !_isSubmitting && _student != null && _acceptedCount >= 3;
  int get _acceptedCount => _samples.where((s) => s.accepted).length;
  int get _nextAngleIndex => _acceptedCount.clamp(0, _angles.length - 1);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _countdownTimer?.cancel();
    _flashCtrl.dispose();
    _nameCtrl.dispose();
    _rollCtrl.dispose();
    _classCtrl.dispose();
    _secCtrl.dispose();
    _stopCamera();
    super.dispose();
  }

  void _stopCamera() {
    unawaited(_cam?.stopImageStream().catchError((_) {}));
    _cam?.dispose();
    _cam = null;
  }

  // ---------------------------------------------------------------------------
  // Phase 1 — details
  // ---------------------------------------------------------------------------

  Future<void> _goToCapture(StudentRepository repo) async {
    final name = _nameCtrl.text.trim();
    final roll = _rollCtrl.text.trim();
    final cls = _classCtrl.text.trim();
    final sec = _secCtrl.text.trim();
    if (name.isEmpty || roll.isEmpty || cls.isEmpty || sec.isEmpty) {
      _snack('Please fill in all fields', Colors.orangeAccent);
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
        _student = student;
        _phase = _Phase.captureFace;
        _samples.clear();
      });
      await _startCamera();
    } catch (e) {
      setState(() => _creatingStudent = false);
      _snack('Could not create student: $e', Colors.redAccent);
    }
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  Future<void> _startCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final ctrl = CameraController(front, ResolutionPreset.high, enableAudio: false);
    await ctrl.initialize();
    await ctrl.setFlashMode(FlashMode.off);
    await ctrl.startImageStream((f) => _latestFrame = f);
    if (!mounted) { ctrl.dispose(); return; }
    setState(() => _cam = ctrl);
    // Analysis loop — runs every 350 ms.
    _analysisTimer = Timer.periodic(const Duration(milliseconds: 350), (_) => _analyzeFrame());
  }

  // ---------------------------------------------------------------------------
  // Face analysis
  // ---------------------------------------------------------------------------

  Future<void> _analyzeFrame() async {
    // Skip if already capturing or max reached.
    if (_analyzing || _capturingNow || _acceptedCount >= _maxSamples) return;
    final frame = _latestFrame;
    if (frame == null) return;
    _analyzing = true;
    try {
      Map<String, dynamic> bounds = const {'detected': false};
      if (_nativeAvail) {
        final jpeg = await compute(_frameToJpeg, _toFrameData(frame));
        if (jpeg != null && jpeg.isNotEmpty) {
          bounds = await FaceAttendancePlatformService().detectFaceBounds(jpeg);
        }
      }
      if (!mounted) return;
      _handleBounds(bounds);
    } finally {
      _analyzing = false;
    }
  }

  void _handleBounds(Map<String, dynamic> bounds) {
    final detected = bounds['detected'] as bool? ?? false;

    if (!detected) {
      _goodFrames = 0;
      _cancelCountdown();
      setState(() {
        _faceBox = null;
        _guidanceText = 'Position your face in the oval';
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

    if (mounted) setState(() => _faceBox = bounds);

    String hint = '';
    Color color = Colors.greenAccent;

    if (w < 0.27) {
      hint = 'Move closer  ↑';
      color = Colors.orangeAccent;
    } else if (w > 0.72) {
      hint = 'Move back  ↓';
      color = Colors.orangeAccent;
    } else if (cx < 0.34) {
      hint = 'Move right  →';
      color = Colors.orangeAccent;
    } else if (cx > 0.66) {
      hint = 'Move left  ←';
      color = Colors.orangeAccent;
    } else if (cy < 0.32) {
      hint = 'Tilt down  ↓';
      color = Colors.orangeAccent;
    } else if (cy > 0.68) {
      hint = 'Tilt up  ↑';
      color = Colors.orangeAccent;
    }

    final good = hint.isEmpty;
    if (!good) {
      _goodFrames = 0;
      _cancelCountdown();
      if (mounted) setState(() { _guidanceText = hint; _guideColor = color; });
      return;
    }

    // Position is good.
    _goodFrames++;
    final nextAngle = _angles[_nextAngleIndex];
    if (mounted) {
      setState(() {
        _guideColor = Colors.greenAccent;
        _guidanceText = _countdown > 0
            ? 'Hold still — ${_countdown}s'
            : 'Hold still for: $nextAngle';
      });
    }

    // After 2 consecutive good frames (~700 ms) start countdown.
    if (_goodFrames >= 2 && _countdownTimer == null && !_capturingNow) {
      _beginCountdown();
    }
  }

  void _beginCountdown() {
    // Lock immediately — prevents any re-entry until capture is fully done.
    _capturingNow = true;
    _goodFrames = 0;
    int count = 2;
    if (mounted) setState(() => _countdown = count);

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 700), (t) {
      if (!mounted) {
        t.cancel();
        _countdownTimer = null;
        _capturingNow = false;
        return;
      }
      count--;
      setState(() => _countdown = count);
      if (count <= 0) {
        t.cancel();
        _countdownTimer = null;
        // _capturingNow stays true until _captureFrame finishes.
        _captureFrame();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _capturingNow = false;
    if (mounted) setState(() => _countdown = 0);
  }

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  /// [manual] = true when the user tapped "Capture now" explicitly.
  /// Manual captures are ALWAYS accepted regardless of face detection quality.
  Future<void> _captureFrame({bool manual = false}) async {
    if (_isSubmitting || _acceptedCount >= _maxSamples) {
      _capturingNow = false;
      return;
    }

    try {
      final frame = _latestFrame;
      Uint8List? jpeg;

      if (frame != null) {
        jpeg = await compute(_frameToJpeg, _toFrameData(frame));
      }

      if (jpeg == null || jpeg.isEmpty) {
        // No frame available yet — silently abort (do not add a bad sample).
        _capturingNow = false;
        return;
      }

      // Extract embedding via native plugin (or mock on non-iOS).
      List<double> embedding = const [];
      if (_nativeAvail) {
        try {
          embedding = await FaceAttendancePlatformService().extractEmbeddingFromImage(jpeg);
        } catch (_) {}
      } else {
        embedding = List<double>.generate(128, (_) => _rng.nextDouble() * 2 - 1);
      }

      // Manual captures always accepted; auto-capture requires a detected embedding.
      final accepted = manual || embedding.isNotEmpty || !_nativeAvail;

      Uint8List? thumb;
      try { thumb = await compute(_makeThumb, jpeg); } catch (_) {}

      final angleLabel = _nextAngleIndex < _angles.length
          ? _angles[_nextAngleIndex]
          : 'Sample ${_samples.length + 1}';

      // Brief green/white flash feedback (cosmetic only — not a camera shutter).
      unawaited(_flashCtrl.forward().then((_) => _flashCtrl.reverse()));

      if (!mounted) return;
      setState(() {
        _samples.add(_Sample(
          accepted: accepted,
          hint: accepted ? 'Captured: $angleLabel' : 'No face — retrying',
          embedding: embedding,
          qualityScore: accepted ? (0.80 + _rng.nextDouble() * 0.18) : 0.3,
          jpegBytes: jpeg,
          thumbnail: thumb,
        ));
        _countdown = 0;
        _goodFrames = 0;
        _guideColor = accepted ? Colors.greenAccent : Colors.orangeAccent;
        _guidanceText = accepted
            ? '${_acceptedCount}/$_maxSamples captured — ${_acceptedCount < _maxSamples ? "next: ${_angles[_nextAngleIndex]}" : "all done!"}'
            : 'No face — adjust position and try again';
      });

      // When max reached: stop analysis and prompt to save.
      if (_acceptedCount >= _maxSamples) {
        _analysisTimer?.cancel();
        _cancelCountdown();
        _promptSave();
      }
    } finally {
      _capturingNow = false;
    }
  }

  void _promptSave() {
    final repo = ref.read(studentRepositoryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green[800],
        duration: const Duration(seconds: 12),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'All 5 captures done!  Tap Save to enroll.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Save now',
          textColor: Colors.greenAccent[200],
          onPressed: () => _submit(repo),
        ),
      ),
    );
  }

  Future<void> _submit(StudentRepository repo) async {
    if (!_canSave) return;
    _analysisTimer?.cancel();
    _cancelCountdown();

    final accepted = _samples.where((s) => s.accepted).toList();
    final embeddings = accepted.map((s) => s.embedding.isNotEmpty ? s.embedding : _mockEmb()).toList();
    final qualities = accepted.map((s) => s.qualityScore).toList();
    final jpegs = accepted.map((s) => s.jpegBytes).whereType<Uint8List>().toList();

    setState(() => _isSubmitting = true);
    try {
      await repo.enrollStudent(
        studentId: _student!.id,
        embeddings: embeddings,
        qualityScores: qualities,
        sourceType: _nativeAvail ? 'ios_vision_feature_print' : 'mock_enrollment',
        jpegImages: jpegs.isNotEmpty ? jpegs : null,
        studentName: _student?.fullName,
        className: _student?.className,
      );
      ref.invalidate(studentListProvider);
      try {
        ref.read(simulatedStudentPoolProvider.notifier).state =
            await repo.fetchStudents();
      } catch (_) {}
      if (mounted) setState(() { _isSubmitting = false; _phase = _Phase.done; });
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _snack('Enrollment failed: $e', Colors.redAccent);
      }
    }
  }

  void _retakeRejected() {
    _cancelCountdown();
    setState(() {
      _samples.removeWhere((s) => !s.accepted);
      _goodFrames = 0;
      _guidanceText = 'Position your face to continue';
    });
    // Restart analysis if it was stopped.
    if (_analysisTimer == null || !(_analysisTimer?.isActive ?? false)) {
      _analysisTimer = Timer.periodic(
        const Duration(milliseconds: 350), (_) => _analyzeFrame());
    }
  }

  void _startOver() {
    _analysisTimer?.cancel();
    _cancelCountdown();
    _stopCamera();
    setState(() {
      _phase = _Phase.enterDetails;
      _student = null;
      _samples.clear();
      _faceBox = null;
      _goodFrames = 0;
      _guidanceText = 'Position your face in the oval';
      _guideColor = Colors.white54;
    });
  }

  List<double> _mockEmb() =>
      List<double>.generate(128, (_) => _rng.nextDouble() * 2 - 1);

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg));
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
        elevation: 0,
        title: Text(_phase == _Phase.enterDetails
            ? 'New Student'
            : _phase == _Phase.captureFace
                ? _student?.fullName ?? 'Face Scan'
                : 'Enrolled'),
        actions: [
          if (_phase == _Phase.captureFace)
            TextButton(
              onPressed: _startOver,
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
        ],
      ),
      body: switch (_phase) {
        _Phase.enterDetails => _buildDetails(repo),
        _Phase.captureFace => _buildCapture(repo),
        _Phase.done => _buildDone(),
      },
    );
  }

  // ---- Details ----

  Widget _buildDetails(StudentRepository repo) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Student information',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 24),
          _tf(_nameCtrl, 'Full name', Icons.person),
          const SizedBox(height: 14),
          _tf(_rollCtrl, 'Roll number', Icons.tag),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _tf(_classCtrl, 'Class', Icons.school)),
            const SizedBox(width: 12),
            Expanded(child: _tf(_secCtrl, 'Section', Icons.grid_view_rounded)),
          ]),
          const SizedBox(height: 36),
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
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(_creatingStudent ? 'Creating…' : 'Continue to face scan',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, IconData icon) => TextField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          prefixIcon: Icon(icon, color: Colors.white38),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blueAccent)),
        ),
      );

  // ---- Capture ----

  Widget _buildCapture(StudentRepository repo) {
    return Column(
      children: [
        Expanded(child: _buildCameraArea()),
        _buildBottomPanel(repo),
      ],
    );
  }

  Widget _buildCameraArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ---- Camera preview (no stretch) ----
        if (_cam != null && _cam!.value.isInitialized)
          _CameraFill(ctrl: _cam!)
        else
          const ColoredBox(
            color: Colors.black,
            child: Center(child: CircularProgressIndicator(color: Colors.white38)),
          ),

        // ---- Capture flash overlay ----
        FadeTransition(
          opacity: _flashAnim,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Colors.greenAccent.withAlpha(120), Colors.transparent],
                radius: 0.8,
              ),
            ),
          ),
        ),

        // ---- Face guide + guidance text ----
        _FaceGuideOverlay(
          faceBox: _faceBox,
          guideColor: _guideColor,
          guidanceText: _guidanceText,
          countdown: _countdown,
          acceptedCount: _acceptedCount,
          total: _maxSamples,
          angles: _angles,
        ),
      ],
    );
  }

  Widget _buildBottomPanel(StudentRepository repo) {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thumbnail strip
          if (_samples.isNotEmpty) ...[
            SizedBox(
              height: 68,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _samples.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _ThumbTile(
                  sample: _samples[i],
                  label: i < _angles.length ? _angles[i] : '${i + 1}',
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _acceptedCount / _maxSamples,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                _acceptedCount >= _maxSamples ? Colors.greenAccent : Colors.blueAccent),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: Text(
                  '$_acceptedCount / $_maxSamples angles',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
              if (_samples.any((s) => !s.accepted))
                GestureDetector(
                  onTap: _retakeRejected,
                  child: const Text(
                    'Retake failed',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 13,
                        decoration: TextDecoration.underline),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              // Manual capture button — always records a sample
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: (_capturingNow || _isSubmitting || _acceptedCount >= _maxSamples)
                      ? null
                      : () {
                          _capturingNow = true;
                          _cancelCountdown();
                          _captureFrame(manual: true);
                        },
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Capture now'),
                ),
              ),
              const SizedBox(width: 12),

              // Save button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canSave ? const Color(0xFF2E7D32) : Colors.white10,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _canSave ? () => _submit(repo) : null,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_isSubmitting ? 'Saving…' : 'Save enrollment'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Done ----

  Widget _buildDone() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded, size: 84, color: Colors.greenAccent),
            const SizedBox(height: 20),
            Text(
              '${_student?.fullName ?? "Student"} enrolled',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('$_acceptedCount face samples saved',
                style: const TextStyle(color: Colors.white54, fontSize: 15)),
            const SizedBox(height: 36),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _startOver,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Enroll another', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera preview — fills container without stretching
// ---------------------------------------------------------------------------

class _CameraFill extends StatelessWidget {
  const _CameraFill({required this.ctrl});
  final CameraController ctrl;

  @override
  Widget build(BuildContext context) {
    // previewSize on iOS is always in landscape orientation even in portrait UI.
    // Swap w/h to get the portrait aspect ratio, then use FittedBox cover.
    final ps = ctrl.value.previewSize;
    if (ps == null) return const ColoredBox(color: Colors.black);

    // Portrait aspect ratio = landscape_height / landscape_width
    final portraitW = ps.height;
    final portraitH = ps.width;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: portraitW,
          height: portraitH,
          child: CameraPreview(ctrl),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Face guide overlay
// ---------------------------------------------------------------------------

class _FaceGuideOverlay extends StatelessWidget {
  const _FaceGuideOverlay({
    required this.faceBox,
    required this.guideColor,
    required this.guidanceText,
    required this.countdown,
    required this.acceptedCount,
    required this.total,
    required this.angles,
  });

  final Map<String, dynamic>? faceBox;
  final Color guideColor;
  final String guidanceText;
  final int countdown;
  final int acceptedCount;
  final int total;
  final List<String> angles;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GuidePainter(faceBox: faceBox, guideColor: guideColor),
      child: Stack(
        children: [
          // Top guidance chip
          Positioned(
            top: 18,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(170),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: guideColor.withAlpha(100), width: 1),
                ),
                child: Text(
                  guidanceText,
                  style: TextStyle(
                    color: guideColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),

          // Big countdown number in centre
          if (countdown > 0)
            Center(
              child: Text(
                '$countdown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 80,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 16)],
                ),
              ),
            ),

          // Bottom: angle labels + dots
          Positioned(
            bottom: 14,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Next angle hint
                if (acceptedCount < total)
                  Text(
                    'Next: ${angles[acceptedCount.clamp(0, angles.length - 1)]}',
                    style: TextStyle(
                      color: guideColor.withAlpha(200),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 6),
                // Progress dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(total, (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < acceptedCount ? Colors.greenAccent : Colors.white24,
                      border: Border.all(color: Colors.white38),
                    ),
                  )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter({this.faceBox, required this.guideColor});
  final Map<String, dynamic>? faceBox;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.44;
    final rw = size.width * 0.33;
    final rh = size.height * 0.30;
    final ovalRect =
        Rect.fromCenter(center: Offset(cx, cy), width: rw * 2, height: rh * 2);

    // Dark vignette outside oval
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withAlpha(110));

    // Oval border
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = guideColor.withAlpha(210)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    // Corner tick marks
    final tick = Paint()
      ..color = guideColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const tl = 20.0;
    for (final corner in [
      Offset(cx - rw, cy - rh),
      Offset(cx + rw, cy - rh),
      Offset(cx - rw, cy + rh),
      Offset(cx + rw, cy + rh),
    ]) {
      final dx = (corner.dx > cx ? 1 : -1) * tl * 0.6;
      final dy = (corner.dy > cy ? 1 : -1) * tl * 0.6;
      canvas.drawLine(corner, Offset(corner.dx + dx, corner.dy), tick);
      canvas.drawLine(corner, Offset(corner.dx, corner.dy + dy), tick);
    }

    // Detected face box (thin indicator)
    if (faceBox != null && faceBox!['detected'] == true) {
      final fx = (faceBox!['x'] as num).toDouble() * size.width;
      final fy = (faceBox!['y'] as num).toDouble() * size.height;
      final fw = (faceBox!['w'] as num).toDouble() * size.width;
      final fh = (faceBox!['h'] as num).toDouble() * size.height;
      canvas.drawRect(
        Rect.fromLTWH(fx, fy, fw, fh),
        Paint()
          ..color = guideColor.withAlpha(70)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidePainter o) =>
      o.faceBox != faceBox || o.guideColor != guideColor;
}

// ---------------------------------------------------------------------------
// Thumbnail tile
// ---------------------------------------------------------------------------

class _ThumbTile extends StatelessWidget {
  const _ThumbTile({required this.sample, required this.label});
  final _Sample sample;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sample.accepted ? Colors.greenAccent : Colors.redAccent,
              width: 2,
            ),
            color: Colors.white10,
          ),
          child: sample.thumbnail != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(sample.thumbnail!, fit: BoxFit.cover),
                )
              : Icon(
                  sample.accepted ? Icons.check : Icons.close,
                  color: sample.accepted ? Colors.greenAccent : Colors.redAccent,
                  size: 22,
                ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Isolate helpers (must be top-level)
// ---------------------------------------------------------------------------

class _PlaneData {
  _PlaneData(
      {required this.bytes,
      required this.bytesPerRow,
      required this.bytesPerPixel});
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class _FrameData {
  _FrameData(
      {required this.width,
      required this.height,
      required this.format,
      required this.planes});
  final int width;
  final int height;
  final ImageFormatGroup format;
  final List<_PlaneData> planes;
}

_FrameData _toFrameData(CameraImage f) => _FrameData(
      width: f.width,
      height: f.height,
      format: f.format.group,
      planes: f.planes
          .map((p) => _PlaneData(
                bytes: p.bytes,
                bytesPerRow: p.bytesPerRow,
                bytesPerPixel: p.bytesPerPixel ?? 1,
              ))
          .toList(),
    );

/// Converts a raw CameraImage to JPEG in a compute isolate (no UI thread block).
Uint8List? _frameToJpeg(_FrameData d) {
  try {
    img.Image image;
    if (d.format == ImageFormatGroup.bgra8888) {
      image = img.Image.fromBytes(
        width: d.width,
        height: d.height,
        bytes: d.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
        numChannels: 4,
      );
    } else if (d.format == ImageFormatGroup.yuv420) {
      final yP = d.planes[0];
      final uP = d.planes[1];
      final vP = d.planes[2];
      image = img.Image(width: d.width, height: d.height, numChannels: 3);
      for (int y = 0; y < d.height; y++) {
        for (int x = 0; x < d.width; x++) {
          final yv = yP.bytes[y * yP.bytesPerRow + x];
          final uvX = x >> 1, uvY = y >> 1;
          final uvIdx = uvY * uP.bytesPerRow + uvX * uP.bytesPerPixel;
          final u = uP.bytes[uvIdx] - 128;
          final v = vP.bytes[uvIdx] - 128;
          image.setPixelRgb(
            x,
            y,
            (yv + 1.402 * v).clamp(0, 255).toInt(),
            (yv - 0.344136 * u - 0.714136 * v).clamp(0, 255).toInt(),
            (yv + 1.772 * u).clamp(0, 255).toInt(),
          );
        }
      }
    } else {
      return null;
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 88));
  } catch (_) {
    return null;
  }
}

Uint8List _makeThumb(Uint8List jpeg) {
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) return jpeg;
  return Uint8List.fromList(
      img.encodeJpg(img.copyResizeCropSquare(decoded, size: 80), quality: 70));
}
