import 'package:flutter_test/flutter_test.dart';

import 'package:face_attendance_flutter/core/models/attendance_event.dart';
import 'package:face_attendance_flutter/core/models/recognition_candidate.dart';
import 'package:face_attendance_flutter/data/repositories/local_queue_repository.dart';

class InMemoryQueueRepository implements LocalQueueRepository {
  final Map<String, AttendanceEvent> _events = {};
  final Set<String> _synced = {};

  @override
  Future<void> enqueue(AttendanceEvent event) async {
    _events[event.eventUuid] = event;
  }

  @override
  Future<void> markSyncedByEventUuid(String eventUuid) async {
    _synced.add(eventUuid);
  }

  @override
  Future<int> pendingCount() async {
    return _events.keys.where((key) => !_synced.contains(key)).length;
  }

  @override
  Future<List<AttendanceEvent>> pendingEvents({int limit = 200}) async {
    return _events.values.where((event) => !_synced.contains(event.eventUuid)).take(limit).toList(growable: false);
  }
}

void main() {
  test('queue stores and marks synced events', () async {
    final repo = InMemoryQueueRepository();
    final event = AttendanceEvent(
      eventUuid: 'evt-1',
      studentId: 'student-1',
      deviceId: 'ipad-kiosk-1',
      timestamp: DateTime.utc(2026, 4, 12, 10, 0, 0),
      method: 'auto',
      confidence: 0.9,
      similarity: 0.88,
      synced: false,
      reviewStatus: 'not_required',
      topCandidates: const [
        RecognitionCandidate(studentId: 'student-1', studentName: 'A', similarity: 0.88, confidence: 0.88),
      ],
    );

    await repo.enqueue(event);
    expect(await repo.pendingCount(), 1);
    await repo.markSyncedByEventUuid('evt-1');
    expect(await repo.pendingCount(), 0);
  });
}
