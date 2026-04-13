import 'package:flutter_test/flutter_test.dart';

import 'package:face_attendance_flutter/core/config/attendance_thresholds.dart';
import 'package:face_attendance_flutter/core/models/recognition_event.dart';
import 'package:face_attendance_flutter/data/services/recognition_decision_engine.dart';

void main() {
  test('auto mark after consecutive frames and stable time', () {
    final engine = RecognitionDecisionEngine(
      const AttendanceThresholds(
        consecutiveFramesRequired: 3,
        minStableTrackingSeconds: 1.0,
        autoMarkThreshold: 0.72,
      ),
    );

    final start = DateTime.utc(2026, 4, 12, 9, 0, 0);
    final event1 = _event(ts: start, similarity: 0.80);
    final event2 = _event(ts: start.add(const Duration(milliseconds: 400)), similarity: 0.81);
    final event3 = _event(ts: start.add(const Duration(milliseconds: 1100)), similarity: 0.82);

    expect(engine.evaluate(event1).type, RecognitionActionType.ignore);
    expect(engine.evaluate(event2).type, RecognitionActionType.ignore);
    expect(engine.evaluate(event3).type, RecognitionActionType.autoMark);
  });

  test('creates review for borderline similarity', () {
    final engine = RecognitionDecisionEngine(const AttendanceThresholds(
      autoMarkThreshold: 0.72,
      reviewThreshold: 0.62,
    ));
    final action = engine.evaluate(_event(ts: DateTime.utc(2026, 4, 12, 9, 0, 0), similarity: 0.65));
    expect(action.type, RecognitionActionType.createReview);
  });
}

RecognitionEvent _event({
  required DateTime ts,
  required double similarity,
}) {
  return RecognitionEvent(
    trackId: 1,
    matchedStudentId: 'student-1',
    matchedStudentName: 'Student 1',
    confidence: similarity,
    similarity: similarity,
    qualityScore: 0.9,
    timestamp: ts,
    imageAcceptedForRecognition: true,
    faceBox: const {'x': 0.1, 'y': 0.1, 'w': 0.2, 'h': 0.2},
  );
}
