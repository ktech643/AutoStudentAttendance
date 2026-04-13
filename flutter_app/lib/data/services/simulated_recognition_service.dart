import 'dart:async';
import 'dart:math';

import '../../core/models/recognition_event.dart';
import '../../core/models/student.dart';

class SimulatedRecognitionService {
  final _controller = StreamController<RecognitionEvent>.broadcast();
  Timer? _timer;
  final Random _random = Random();
  List<Student> _studentPool = const [];

  Stream<RecognitionEvent> stream() => _controller.stream;

  void setStudentPool(List<Student> students) {
    _studentPool = List<Student>.from(students);
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      final now = DateTime.now().toUtc();
      final trackId = _random.nextInt(4) + 1;
      final enrollable = _studentPool.where((s) => s.isActive && s.embeddingCount > 0).toList(growable: false);
      final bool matched;
      final String? sid;
      final String? sname;
      final String? sroll;

      if (enrollable.isNotEmpty && _random.nextDouble() > 0.35) {
        final student = enrollable[_random.nextInt(enrollable.length)];
        matched = true;
        sid = student.id;
        sname = student.fullName;
        sroll = student.rollNumber;
      } else {
        matched = false;
        sid = null;
        sname = null;
        sroll = null;
      }

      final similarity = matched ? 0.72 + _random.nextDouble() * 0.22 : 0.50 + _random.nextDouble() * 0.20;
      _controller.add(
        RecognitionEvent(
          trackId: trackId,
          matchedStudentId: sid,
          matchedStudentName: sname,
          matchedStudentRollNumber: sroll,
          confidence: similarity,
          similarity: similarity,
          qualityScore: 0.80 + _random.nextDouble() * 0.20,
          timestamp: now,
          imageAcceptedForRecognition: true,
          faceBox: const {'x': 0.2, 'y': 0.2, 'w': 0.25, 'h': 0.25},
        ),
      );
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
