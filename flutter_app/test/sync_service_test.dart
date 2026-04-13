import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_attendance_flutter/core/models/attendance_event.dart';
import 'package:face_attendance_flutter/data/repositories/attendance_repository.dart';
import 'package:face_attendance_flutter/data/repositories/local_queue_repository.dart';
import 'package:face_attendance_flutter/data/services/sync_service.dart';

class FakeAttendanceRepository implements AttendanceRepository {
  final List<AttendanceEvent> submitted = [];

  @override
  Future<void> bulkSync(List<AttendanceEvent> events) async {
    submitted.addAll(events);
  }

  @override
  Future<List<AttendanceEvent>> fetchRecent({int limit = 20}) async => const [];

  @override
  Future<void> submitEvent(AttendanceEvent event) async {
    submitted.add(event);
  }
}

class FakeLocalQueueRepository implements LocalQueueRepository {
  final List<AttendanceEvent> events;
  final Set<String> synced = {};

  FakeLocalQueueRepository(this.events);

  @override
  Future<void> enqueue(AttendanceEvent event) async {}

  @override
  Future<void> markSyncedByEventUuid(String eventUuid) async {
    synced.add(eventUuid);
  }

  @override
  Future<int> pendingCount() async => events.where((e) => !synced.contains(e.eventUuid)).length;

  @override
  Future<List<AttendanceEvent>> pendingEvents({int limit = 200}) async {
    return events.where((e) => !synced.contains(e.eventUuid)).toList(growable: false);
  }
}

void main() {
  test('sync service flushes pending queue', () async {
    final event = AttendanceEvent(
      eventUuid: 'evt-2',
      studentId: 's1',
      deviceId: 'ipad',
      timestamp: DateTime.utc(2026, 4, 12, 10, 0, 0),
      method: 'auto',
      confidence: 0.9,
      similarity: 0.9,
      synced: false,
      reviewStatus: 'not_required',
    );
    final attendanceRepo = FakeAttendanceRepository();
    final queueRepo = FakeLocalQueueRepository([event]);

    final service = SyncService(
      attendanceRepository: attendanceRepo,
      localQueueRepository: queueRepo,
      connectivity: Connectivity(),
    );

    await service.flushPending();
    expect(attendanceRepo.submitted.length, 1);
    expect(queueRepo.synced.contains('evt-2'), isTrue);
  });
}
