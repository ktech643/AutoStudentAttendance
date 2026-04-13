import 'dart:async' show Timer, unawaited;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/student.dart';
import '../../data/repositories/student_repository.dart';
import '../providers/providers.dart';
import '../widgets/face_camera_view.dart';

enum _EnrollmentPhase { enterDetails, captureFace }

class _EnrollmentSample {
  const _EnrollmentSample({
    required this.qualityScore,
    required this.accepted,
    required this.hint,
  });

  final double qualityScore;
  final bool accepted;
  final String hint;
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

  /// Bumps each time we enter the camera step so [FaceCameraView] fully remounts (fixes 2nd visit / web).
  int _cameraSession = 0;

  bool _creatingStudent = false;
  bool _isSubmittingEnrollment = false;
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
    if (mounted) {
      setState(() => _autoRunning = false);
    } else {
      _autoRunning = false;
    }
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
        fullName: name,
        className: className,
        section: section,
        rollNumber: roll,
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
        _status = 'When the preview appears, tap “Start auto capture”.';
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

  /// Auto mode uses a higher pass rate so enrollment completes reliably (embeddings are still mock vectors).
  void _captureSample({required bool autoMode}) {
    if (_isSubmittingEnrollment) {
      return;
    }
    if (_samples.length >= 10) {
      setState(() => _status = 'Maximum 10 samples reached');
      _stopAutoCapture();
      return;
    }

    late final bool accepted;
    late final double qualityScore;
    late final String hint;

    if (autoMode) {
      accepted = _random.nextDouble() < 0.85;
      qualityScore = (0.72 + _random.nextDouble() * 0.26).clamp(0.0, 1.0);
      hint = accepted ? 'Auto capture — good' : 'Auto capture — will retry if needed';
    } else {
      final blurScore = 50 + _random.nextInt(120);
      final brightness = 20 + _random.nextInt(90);
      final yaw = _random.nextDouble() * 35;
      qualityScore = (blurScore / 170 + brightness / 110 + (35 - yaw) / 35) / 3;
      accepted = blurScore >= 90 && brightness >= 35 && yaw <= 20;
      hint = accepted
          ? 'Good quality'
          : blurScore < 90
              ? 'Blurry — hold still'
              : brightness < 35
                  ? 'Improve lighting'
                  : 'Face the camera squarely';
    }

    setState(() {
      _samples.add(
        _EnrollmentSample(
          qualityScore: qualityScore.clamp(0, 1).toDouble(),
          accepted: accepted,
          hint: hint,
        ),
      );
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
    if (autoMode && _samples.length >= 10) {
      _stopAutoCapture();
    }
  }

  void _beginAutoCapture() {
    if (_autoRunning) {
      return;
    }
    _stopAutoCapture();
    setState(() {
      _autoRunning = true;
      _status = 'Auto capture running…';
    });
    _autoTimer = Timer.periodic(const Duration(milliseconds: 2200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_samples.length >= 10) {
        _stopAutoCapture();
        return;
      }
      _captureSample(autoMode: true);
    });
  }

  void _retryLowQuality() {
    setState(() {
      _samples.removeWhere((sample) => !sample.accepted);
      _status = 'Low-quality samples removed.';
    });
  }

  String _buildStatus() {
    final accepted = _samples.where((sample) => sample.accepted).length;
    if (accepted >= 5) {
      return accepted >= 8 ? 'Quality: strong — you can finish' : 'Quality: OK — add more if you like';
    }
    return 'Accepted $accepted / 5 minimum • ${_samples.length} total samples';
  }

  Future<void> _submit(StudentRepository repository, {bool silent = false}) async {
    final studentId = _createdStudent?.id;
    if (studentId == null) {
      return;
    }
    final acceptedList = _samples.where((sample) => sample.accepted).toList(growable: false);
    if (acceptedList.length < 5) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Need at least 5 accepted samples.')),
        );
      }
      return;
    }

    setState(() => _isSubmittingEnrollment = true);
    final embeddings = acceptedList.map((_) => _mockEmbedding()).toList(growable: false);
    final qualities = acceptedList.map((sample) => sample.qualityScore).toList(growable: false);
    try {
      await repository.enrollStudent(
        studentId: studentId,
        embeddings: embeddings,
        qualityScores: qualities,
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
            content: Text(
              silent ? 'Enrollment saved automatically.' : 'Enrollment complete. Open Kiosk to test.',
            ),
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

  List<double> _mockEmbedding() {
    return List<double>.generate(
      128,
      (_) => (_random.nextDouble() * 2 - 1),
      growable: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(studentRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll student'),
        actions: [
          if (_phase == _EnrollmentPhase.captureFace) ...[
            if (_autoRunning)
              TextButton(
                onPressed: _stopAutoCapture,
                child: const Text('Stop auto'),
              ),
            TextButton(
              onPressed: _startOver,
              child: const Text('Start over'),
            ),
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
            'Enter name and roll number. Next step uses the camera and captures samples automatically with on-screen tips.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Full name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rollController,
            decoration: const InputDecoration(
              labelText: 'Roll number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _classController,
            decoration: const InputDecoration(
              labelText: 'Class',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sectionController,
            decoration: const InputDecoration(
              labelText: 'Section',
              border: OutlineInputBorder(),
            ),
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
              child: Text(
                '${student.fullName} • Roll ${student.rollNumber ?? "—"} • ${student.className}-${student.section}',
                style: Theme.of(context).textTheme.titleMedium,
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
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            if (c != null && c.value.isInitialized) {
                              _status = 'Camera ready — tap “Start auto capture”';
                            } else {
                              _status = 'No camera — tap “Start auto capture” for simulated samples.';
                            }
                          });
                        },
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 16,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _instructions[_instructionTick % _instructions.length],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
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
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: !_autoRunning ? _beginAutoCapture : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start auto capture'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _autoRunning ? null : () => _captureSample(autoMode: false),
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
                    height: constraints.hasBoundedHeight
                        ? min(140.0, constraints.maxHeight * 0.2)
                        : 140.0,
                    child: ListView.builder(
                      itemCount: _samples.length,
                      itemBuilder: (context, index) {
                        final sample = _samples[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            sample.accepted ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: sample.accepted ? Colors.green : Colors.orange,
                          ),
                          title: Text('${index + 1}. ${(sample.qualityScore * 100).toStringAsFixed(0)}% • ${sample.hint}'),
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
