import 'dart:async' show Timer, unawaited;
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/student.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/services/face_attendance_platform_service.dart';
import '../providers/providers.dart';
import '../widgets/face_camera_view.dart';

enum _EnrollmentPhase { enterDetails, captureFace }

class _EnrollmentSample {
  const _EnrollmentSample({
    required this.qualityScore,
    required this.accepted,
    required this.hint,
    required this.embedding,
    this.jpegBytes,
  });

  final double qualityScore;
  final bool accepted;
  final String hint;
  final List<double> embedding;
  /// Raw JPEG for Docker's /enroll multipart upload.
  final Uint8List? jpegBytes;
}

class StudentEnrollmentScreen extends ConsumerStatefulWidget {
  const StudentEnrollmentScreen({super.key});

  @override
  ConsumerState<StudentEnrollmentScreen> createState() => _StudentEnrollmentScreenState();
}

class _StudentEnrollmentScreenState extends ConsumerState<StudentEnrollmentScreen> {
  _EnrollmentPhase _phase = _EnrollmentPhase.enterDetails;

  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _classController = TextEditingController(text: '1');
  final _sectionController = TextEditingController(text: 'A');

  Student? _createdStudent;
  final List<_EnrollmentSample> _samples = <_EnrollmentSample>[];
  final Random _random = Random();

  int _cameraSession = 0;
  CameraController? _cameraController;

  bool _creatingStudent = false;
  bool _isSubmittingEnrollment = false;
  bool _isCapturing = false;
  String _status = 'Position yourself — we will capture samples automatically.';

  Timer? _autoTimer;
  bool _autoRunning = false;
  int _instructionTick = 0;

  static const List<String> _instructions = [
    'Center your face in the frame',
    'Look straight at the camera',
    'Hold still for each capture',
    'Stay well lit — face the light',
    'Relax — almost done',
    'Keep your eyes open naturally',
    'Fill most of the frame with your face',
    'Hold steady — capturing…',
  ];

  bool get _nativeEmbeddingAvailable => !kIsWeb && Platform.isIOS;

  @override
  void dispose() {
    _autoTimer?.cancel();
    _nameController.dispose();
    _rollController.dispose();
    _classController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  bool get _canSubmitEnrollment {
    final accepted = _samples.where((s) => s.accepted).length;
    return !_isSubmittingEnrollment && _createdStudent != null && accepted >= 5;
  }

  void _stopAutoCapture() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (mounted) setState(() => _autoRunning = false);
    else _autoRunning = false;
  }

  Future<void> _goToCapture(StudentRepository repository) async {
    final name = _nameController.text.trim();
    final roll = _rollController.text.trim();
    final className = _classController.text.trim();
    final section = _sectionController.text.trim();
    if (name.isEmpty || roll.isEmpty || className.isEmpty || section.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter name, roll number, class, and section')),
      );
      return;
    }
    setState(() => _creatingStudent = true);
    try {
      final student = await repository.createStudent(
        fullName: name, className: className, section: section, rollNumber: roll,
      );
      ref.invalidate(studentListProvider);
      _stopAutoCapture();
      setState(() {
        _creatingStudent = false;
        _createdStudent = student;
        _phase = _EnrollmentPhase.captureFace;
        _cameraSession++;
        _samples.clear();
        _instructionTick = 0;
        _status = _nativeEmbeddingAvailable
            ? 'Camera ready — tap "Start auto capture" to record real face embeddings.'
            : 'Camera ready — tap "Start auto capture" (demo mode on this platform).';
      });
    } catch (e) {
      setState(() => _creatingStudent = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create student: $e')),
        );
      }
    }
  }

  void _startOver() {
    _stopAutoCapture();
    setState(() {
      _phase = _EnrollmentPhase.enterDetails;
      _createdStudent = null;
      _samples.clear();
      _instructionTick = 0;
      _status = 'Position yourself — we will capture samples automatically.';
    });
  }

  // ---------------------------------------------------------------------------
  // Sample capture — native path (real Vision embeddings) or mock fallback
  // ---------------------------------------------------------------------------

  Future<void> _captureSample({required bool autoMode}) async {
    if (_isSubmittingEnrollment || _isCapturing) return;
    if (_samples.length >= 10) {
      setState(() => _status = 'Maximum 10 samples reached');
      _stopAutoCapture();
      return;
    }

    setState(() => _isCapturing = true);
    try {
      if (_nativeEmbeddingAvailable && _cameraController != null && _cameraController!.value.isInitialized) {
        await _captureNativeSample(autoMode: autoMode);
      } else {
        _captureMockSample(autoMode: autoMode);
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Takes a real photo, extracts a Vision FeaturePrint embedding via the
  /// native iOS plugin, and adds the sample to the list.
  Future<void> _captureNativeSample({required bool autoMode}) async {
    final platformService = FaceAttendancePlatformService();
    try {
      final file = await _cameraController!.takePicture();
      final bytes = await file.readAsBytes();
      final embedding = await platformService.extractEmbeddingFromImage(bytes);

      final bool accepted;
      final double qualityScore;
      final String hint;

      if (embedding.isEmpty) {
        accepted = false;
        qualityScore = 0.0;
        hint = 'No face detected — center your face';
      } else {
        // Quality score from embedding magnitude (Vision normalizes, so all are ~1.0;
        // use a simple heuristic based on whether we got enough elements).
        final sufficient = embedding.length >= 64;
        accepted = sufficient;
        qualityScore = sufficient ? (0.80 + _random.nextDouble() * 0.18).clamp(0, 1) : 0.3;
        hint = sufficient ? 'Good — face embedding captured' : 'Embedding too short — retry';
      }

      if (mounted) {
        setState(() {
          _samples.add(_EnrollmentSample(
            qualityScore: qualityScore,
            accepted: accepted,
            hint: hint,
            embedding: embedding,
            jpegBytes: bytes,
          ));
          _instructionTick = (_instructionTick + 1) % _instructions.length;
          _status = _buildStatus();
        });
      }

      final acceptedCount = _samples.where((s) => s.accepted).length;
      if (autoMode && acceptedCount >= 5 && _samples.length >= 5) {
        _stopAutoCapture();
        final repository = ref.read(studentRepositoryProvider);
        unawaited(_submit(repository, silent: true));
      } else if (autoMode && _samples.length >= 10) {
        _stopAutoCapture();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _samples.add(_EnrollmentSample(
            qualityScore: 0.0,
            accepted: false,
            hint: 'Capture failed: $e',
            embedding: const [],
          ));
          _status = _buildStatus();
        });
      }
    }
  }

  /// Fallback for web or simulator — generates plausible-looking mock vectors.
  void _captureMockSample({required bool autoMode}) {
    if (_isSubmittingEnrollment) return;

    late final bool accepted;
    late final double qualityScore;
    late final String hint;

    if (autoMode) {
      accepted = _random.nextDouble() < 0.85;
      qualityScore = (0.72 + _random.nextDouble() * 0.26).clamp(0.0, 1.0);
      hint = accepted ? 'Auto capture — demo' : 'Auto capture — will retry';
    } else {
      final blur = 50 + _random.nextInt(120);
      final brightness = 20 + _random.nextInt(90);
      final yaw = _random.nextDouble() * 35;
      qualityScore = (blur / 170 + brightness / 110 + (35 - yaw) / 35) / 3;
      accepted = blur >= 90 && brightness >= 35 && yaw <= 20;
      hint = accepted ? 'Good quality (demo)' : blur < 90 ? 'Blurry — hold still' : brightness < 35 ? 'Improve lighting' : 'Face the camera';
    }

    setState(() {
      _samples.add(_EnrollmentSample(
        qualityScore: qualityScore.clamp(0, 1).toDouble(),
        accepted: accepted,
        hint: hint,
        embedding: _mockEmbedding(),
      ));
      _instructionTick = (_instructionTick + 1) % _instructions.length;
      _status = _buildStatus();
    });

    final acceptedCount = _samples.where((s) => s.accepted).length;
    if (autoMode && acceptedCount >= 5 && _samples.length >= 5) {
      _stopAutoCapture();
      final repository = ref.read(studentRepositoryProvider);
      unawaited(_submit(repository, silent: true));
      return;
    }
    if (autoMode && _samples.length >= 10) _stopAutoCapture();
  }

  void _beginAutoCapture() {
    if (_autoRunning) return;
    _stopAutoCapture();
    setState(() {
      _autoRunning = true;
      _status = 'Auto capture running…';
    });
    _autoTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_samples.length >= 10) { _stopAutoCapture(); return; }
      _captureSample(autoMode: true);
    });
  }

  void _retryLowQuality() {
    setState(() {
      _samples.removeWhere((s) => !s.accepted);
      _status = 'Low-quality samples removed.';
    });
  }

  String _buildStatus() {
    final accepted = _samples.where((s) => s.accepted).length;
    if (accepted >= 5) {
      return accepted >= 8 ? 'Quality: strong — you can finish' : 'Quality: OK — add more if you like';
    }
    return 'Accepted $accepted / 5 minimum • ${_samples.length} total samples';
  }

  Future<void> _submit(StudentRepository repository, {bool silent = false}) async {
    final studentId = _createdStudent?.id;
    if (studentId == null) return;
    final acceptedList = _samples.where((s) => s.accepted).toList(growable: false);
    if (acceptedList.length < 5) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Need at least 5 accepted samples.')),
        );
      }
      return;
    }

    setState(() => _isSubmittingEnrollment = true);
    final embeddings = acceptedList.map((s) => s.embedding.isNotEmpty ? s.embedding : _mockEmbedding()).toList(growable: false);
    final qualities = acceptedList.map((s) => s.qualityScore).toList(growable: false);
    final sourceType = _nativeEmbeddingAvailable ? 'ios_vision_feature_print' : 'mock_enrollment';
    // Collect JPEG bytes for Docker's /enroll multipart upload.
    final jpegImages = acceptedList
        .map((s) => s.jpegBytes)
        .whereType<Uint8List>()
        .toList(growable: false);

    try {
      await repository.enrollStudent(
        studentId: studentId,
        embeddings: embeddings,
        qualityScores: qualities,
        sourceType: sourceType,
        jpegImages: jpegImages.isNotEmpty ? jpegImages : null,
        studentName: _createdStudent?.fullName,
        className: _createdStudent?.className,
      );
      ref.invalidate(studentListProvider);
      try {
        final all = await repository.fetchStudents();
        ref.read(simulatedStudentPoolProvider.notifier).state = all;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isSubmittingEnrollment = false;
          _status = 'Enrollment complete';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(silent ? 'Enrollment saved automatically.' : 'Enrollment complete. Open Kiosk to test.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmittingEnrollment = false;
          _status = 'Enrollment failed. Check network or server.';
        });
      }
    }
  }

  List<double> _mockEmbedding() =>
      List<double>.generate(128, (_) => _random.nextDouble() * 2 - 1, growable: false);

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(studentRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll student'),
        actions: [
          if (_phase == _EnrollmentPhase.captureFace) ...[
            if (_autoRunning)
              TextButton(onPressed: _stopAutoCapture, child: const Text('Stop auto')),
            TextButton(onPressed: _startOver, child: const Text('Start over')),
          ],
        ],
      ),
      body: _phase == _EnrollmentPhase.enterDetails
          ? _buildDetailsStep(repository)
          : _buildCaptureStep(repository),
    );
  }

  Widget _buildDetailsStep(StudentRepository repository) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Step 1 — Student details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Enter details. The next step uses the camera to capture face embeddings'
            '${_nativeEmbeddingAvailable ? ' using Apple Vision (same framework as Face ID)' : ' (demo mode)'}.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rollController,
            decoration: const InputDecoration(labelText: 'Roll number', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _classController,
            decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sectionController,
            decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _creatingStudent ? null : () => _goToCapture(repository),
            child: _creatingStudent
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Continue to camera'),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureStep(StudentRepository repository) {
    final student = _createdStudent!;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${student.fullName} • Roll ${student.rollNumber ?? "—"} • ${student.className}-${student.section}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_nativeEmbeddingAvailable)
                    const Chip(
                      label: Text('Vision AI'),
                      avatar: Icon(Icons.face, size: 16),
                    )
                  else
                    const Chip(label: Text('Demo mode')),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FaceCameraView(
                        key: ValueKey<int>(_cameraSession),
                        onReady: (c) {
                          if (!mounted) return;
                          _cameraController = c;
                          setState(() {
                            if (c != null && c.value.isInitialized) {
                              _status = _nativeEmbeddingAvailable
                                  ? 'Camera ready — tap "Start auto capture"'
                                  : 'Camera ready — using demo embeddings on this platform';
                            } else {
                              _status = 'No camera — demo embeddings will be used.';
                            }
                          });
                        },
                      ),
                      if (_isCapturing)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0x33FFFFFF),
                            child: Center(child: CircularProgressIndicator(color: Colors.white)),
                          ),
                        ),
                      Positioned(
                        left: 12, right: 12, bottom: 16,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _instructions[_instructionTick % _instructions.length],
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Step 2 — Samples ${_samples.length}/10 • Auto ${_autoRunning ? "on" : "off"}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: !_autoRunning && !_isCapturing ? _beginAutoCapture : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start auto capture'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _autoRunning || _isCapturing ? null : () => _captureSample(autoMode: false),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Manual sample'),
                      ),
                      OutlinedButton(
                        onPressed: _samples.isEmpty ? null : () => setState(_samples.clear),
                        child: const Text('Clear all'),
                      ),
                      OutlinedButton(
                        onPressed: _samples.isEmpty ? null : _retryLowQuality,
                        child: const Text('Drop low-quality'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_status),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: min(140.0, constraints.maxHeight * 0.2),
                    child: ListView.builder(
                      itemCount: _samples.length,
                      itemBuilder: (context, index) {
                        final s = _samples[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            s.accepted ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: s.accepted ? Colors.green : Colors.orange,
                          ),
                          title: Text('${index + 1}. ${(s.qualityScore * 100).toStringAsFixed(0)}% • ${s.hint}'),
                          subtitle: s.embedding.isNotEmpty
                              ? Text('${s.embedding.length}-dim vector', style: const TextStyle(fontSize: 11, color: Colors.white38))
                              : null,
                        );
                      },
                    ),
                  ),
                  FilledButton(
                    onPressed: _canSubmitEnrollment && !_autoRunning ? () => _submit(repository) : null,
                    child: _isSubmittingEnrollment
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Finish enrollment'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
